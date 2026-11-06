import Foundation
import NtfyCore
import NtfyIPC
import NtfyPlatform
import NtfyTesting
import Synchronization

@testable import NtfyMacCLI

/// Collects what a command wrote to stdout and stderr.
final class Capture: Sendable {
  private let text = Mutex<(out: String, err: String)>(("", ""))

  func out(_ chunk: String) { text.withLock { $0.out += chunk } }
  func err(_ chunk: String) { text.withLock { $0.err += chunk } }
  var stdout: String { text.withLock { $0.out } }
  var stderr: String { text.withLock { $0.err } }
}

struct RunResult {
  let exit: ProcessExit
  let stdout: String
  let stderr: String

  var stdoutLines: [String] { stdout.split(separator: "\n").map(String.init) }

  /// The one JSON document on stdout, as a dictionary.
  func json() throws -> [String: Any] {
    let lines = stdoutLines
    guard lines.count == 1, let data = lines.first?.data(using: .utf8),
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw RigError.notOneJSONDocument(stdout) }
    return object
  }
}

enum RigError: Error { case notOneJSONDocument(String) }

/// A throwaway directory removed when the rig goes away.
final class Scratch: Sendable {
  let url = FileManager.default.temporaryDirectory
    .appendingPathComponent("ntfy-mac-cli-\(UUID().uuidString)", isDirectory: true)

  init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
  deinit { try? FileManager.default.removeItem(at: url) }

  func file(_ path: String) -> URL { url.appendingPathComponent(path) }

  func write(_ content: String, to path: String) throws {
    let target = file(path)
    try FileManager.default.createDirectory(
      at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(content.utf8).write(to: target)
  }
}

actor FakeApp: AppControlling {
  struct Call {
    let request: Request
    let launch: Bool
  }

  private(set) var calls: [Call] = []
  private var replies: [Command: Response] = [:]
  private let failure: NtfyError?

  init(failure: NtfyError? = nil) { self.failure = failure }

  func reply(to command: Command, with response: Response) { replies[command] = response }

  func commands() -> [Command] { calls.map(\.request.command) }

  func send(_ request: Request, launch: Bool) async throws(NtfyError) -> Response {
    calls.append(Call(request: request, launch: launch))
    if let failure { throw failure }
    return replies[request.command] ?? Self.defaultReply(request)
  }

  private static func defaultReply(_ request: Request) -> Response {
    let result: ResultPayload? =
      switch request.command {
      case .status:
        ResultPayload(
          status: StatusResult(
            connection: "connected", appVersion: Version.current,
            permission: PermissionSummary(usable: true)))
      case .permission: ResultPayload(permission: PermissionSummary(usable: true))
      case .notify: ResultPayload(notify: NotifyResult(posted: true))
      case .ackAll: ResultPayload(ackAll: AckAllResult(acknowledged: 0))
      case .delete: ResultPayload(delete: DeleteResult(deleted: request.delete?.id == nil ? 0 : 1))
      case .update:
        ResultPayload(
          update: UpdateStatusPayload(channel: "direct", currentVersion: Version.current))
      case .loginItem:
        ResultPayload(
          loginItem: LoginItemResult(
            state: request.loginItem?.action == .disable
              ? LoginItemState.notRegistered.rawValue : LoginItemState.enabled.rawValue))
      default: nil
      }
    return .success(id: request.id, result: result)
  }
}

actor FakeProcesses: ProcessRunning {
  struct Run: Equatable {
    let executable: String
    let arguments: [String]
  }

  private(set) var runs: [Run] = []
  private let status: Int32

  init(status: Int32 = 0) { self.status = status }

  func run(
    _ executable: String, _ arguments: [String], output: ChildOutput
  ) async throws(NtfyError) -> Int32 {
    runs.append(Run(executable: executable, arguments: arguments))
    return status
  }
}

/// Publishes nothing; remembers what it was asked and answers with a fixed id.
actor StubPublisher: NtfyPublishing {
  private(set) var requests: [PublishRequest] = []
  private let failure: NtfyError?
  private let time: Date

  init(failure: NtfyError? = nil, time: Date) {
    self.failure = failure
    self.time = time
  }

  func publish(_ request: PublishRequest) async throws(NtfyError) -> PublishedMessage {
    requests.append(request)
    if let failure { throw failure }
    return PublishedMessage(id: "pub1", topic: request.topic, time: time)
  }
}

/// History in memory: `absent` is a database the app has not created yet.
struct FakeHistory: HistoryOpening {
  let store: InMemoryHistoryStore
  var absent = false

  func reader(server: String) throws(NtfyError) -> (any HistoryInbox)? {
    absent ? nil : store
  }

  func writer(server: String) throws(NtfyError) -> any HistoryInbox { store }
}

struct FakeReleases: ReleaseLookup {
  var tag = "v2.0.0"
  var failure: NtfyError?

  func latest() async throws(NtfyError) -> LatestRelease {
    if let failure { throw failure }
    return LatestRelease(tag: tag)
  }
}

final class ScriptedPrompter: Prompting {
  private let answers: Mutex<[String]>
  private let secrets: Mutex<[String]>

  init(answers: [String] = [], secrets: [String] = []) {
    self.answers = Mutex(answers)
    self.secrets = Mutex(secrets)
  }

  func ask(_ question: String, default defaultValue: String?) -> String? {
    answers.withLock { $0.isEmpty ? nil : $0.removeFirst() } ?? defaultValue
  }

  func askSecret(_ question: String) -> String? {
    secrets.withLock { $0.isEmpty ? nil : $0.removeFirst() }
  }
}

/// A CLI environment made of fakes, rooted in a scratch directory. Never touches the real
/// config, Keychain, socket or network.
struct CLIRig {
  static let serverURL = "https://ntfy.test"

  let scratch = Scratch()
  let config: InMemoryConfigStore
  let secrets: InMemorySecretStore
  let topics: ScriptedTopicSource
  let app: FakeApp
  let processes: FakeProcesses
  let launchAgents = InMemoryLaunchAgents()
  let launchServices = InMemoryLaunchServices()
  let legacyProcesses = InMemoryLegacyProcesses()
  let clock = FakeClock()
  let store: InMemoryHistoryStore
  var historyAbsent = false
  var publishFailure: NtfyError?
  var releases = FakeReleases()
  var prompter = ScriptedPrompter()
  var terminal = Terminal(stdinIsTTY: false, stdoutIsTTY: false)
  var stdin = Data()
  var executablePath: String
  var variables: [String: String] = [:]
  var appCandidates: [URL] = []
  /// What the CLI reads from its own bundle's signature (a development build by default).
  var signing = SigningInfo.unsigned
  /// The Team ID the app recorded, if any.
  var recordedTeam: String?

  init(
    configured: Bool = true, topics: [String] = ["alerts"], topicFailure: NtfyError? = nil,
    app: FakeApp = FakeApp(), processes: FakeProcesses = FakeProcesses()
  ) {
    config = InMemoryConfigStore(configured ? Config(url: Self.serverURL) : Config())
    secrets = InMemorySecretStore(token: configured ? "tk_secret" : nil)
    self.topics = ScriptedTopicSource(topics: topics, failingWith: topicFailure)
    self.app = app
    self.processes = processes
    store = InMemoryHistoryStore(clock: clock)
    executablePath = scratch.file("Applications/NtfyMac.app/Contents/MacOS/ntfy-mac").path
    let sounds = scratch.file("sounds")
    for name in ["Ping.aiff", "Pop.aiff", "Sosumi.aiff", "Tink.aiff"] {
      try? scratch.write("", to: "sounds/\(name)")
    }
    _ = sounds
  }

  var paths: CLIPaths {
    var paths = CLIPaths(
      environment: [
        CLIPaths.configDirectoryVariable: scratch.file("config").path,
        CLIPaths.dataDirectoryVariable: scratch.file("data").path,
      ], home: scratch.url, systemApplicationSupport: scratch.file("Support"))
    paths.soundDirectories = [scratch.file("sounds")]
    return paths
  }

  var environment: CLIEnvironment {
    let source = topics
    let input = stdin
    let publisher = StubPublisher(failure: publishFailure, time: clock.now())
    return CLIEnvironment(
      paths: paths, variables: variables, terminal: terminal, executablePath: executablePath,
      config: config, secrets: secrets, app: app,
      topicSource: { _, _, _ in source }, publisher: { _, _, _ in publisher },
      history: FakeHistory(store: store, absent: historyAbsent), clock: clock,
      runUntilInterrupted: { try await $0() }, processes: processes, releases: releases,
      signing: FixedSigning(signing), teamPins: InMemoryTeamPinStore(recordedTeam),
      legacy: LegacyInstallCleanup(
        layout: LegacyInstallLayout(
          home: scratch.url, uid: 501, stateDirectory: paths.stateDirectory,
          brewPrefixes: [scratch.file("brew")]),
        agents: launchAgents, registry: launchServices, processes: legacyProcesses,
        runningExecutable: nil, processID: 1234),
      appCandidates: appCandidates,
      prompter: prompter, readStandardInput: { input })
  }

  /// Adds a message to the history `age` seconds before the rig's clock.
  @discardableResult
  func add(
    _ topic: String = "alerts", id: String, body: String = "body", title: String? = nil,
    priority: Int = 3, age: TimeInterval = 0, tags: [String] = []
  ) async -> NtfyMessage {
    let message = NtfyMessage(
      id: id, topic: topic, time: clock.now().addingTimeInterval(-age), title: title, body: body,
      priority: Priority(clamping: priority), tags: tags)
    _ = try? await store.append(message)
    return message
  }

  func run(_ arguments: String...) async -> RunResult {
    await run(arguments)
  }

  func run(_ arguments: [String]) async -> RunResult {
    let capture = Capture()
    let exit = await CLIEntry.run(arguments, environment: environment) { json in
      Output(json: json, stdout: capture.out, stderr: capture.err)
    }
    return RunResult(exit: exit, stdout: capture.stdout, stderr: capture.stderr)
  }
}

extension CLIRig {
  /// Runs a command that sleeps on the rig's clock, moving the clock forward until it ends.
  /// `during` runs once the command is waiting, to add history while it blocks.
  func runAdvancing(
    _ arguments: [String], step: Duration = .milliseconds(500),
    during: (@Sendable (CLIRig) async -> Void)? = nil
  ) async -> RunResult {
    let finished = Mutex(false)
    let task = Task {
      let result = await run(arguments)
      finished.withLock { $0 = true }
      return result
    }
    var rounds = 0
    var injected = during == nil
    while !finished.withLock({ $0 }), rounds < 20_000 {
      rounds += 1
      if clock.sleeperCount > 0 {
        if !injected, let during {
          injected = true
          await during(self)
        }
        clock.advance(by: step)
      }
      try? await Task.sleep(for: .milliseconds(1))
    }
    return await task.value
  }
}
