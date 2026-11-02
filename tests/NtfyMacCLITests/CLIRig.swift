import Foundation
import NtfyCore
import NtfyIPC
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

struct FakeReleases: ReleaseLookup {
  var tag = "v2.0.0"
  var failure: NtfyError?

  func latestTag() async throws(NtfyError) -> String {
    if let failure { throw failure }
    return tag
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
  var releases = FakeReleases()
  var prompter = ScriptedPrompter()
  var terminal = Terminal(stdinIsTTY: false, stdoutIsTTY: false)
  var stdin = Data()
  var executablePath = "/Applications/NtfyMac.app/Contents/MacOS/ntfy-mac"
  var variables: [String: String] = [:]

  init(
    configured: Bool = true, topics: [String] = ["alerts"], topicFailure: NtfyError? = nil,
    app: FakeApp = FakeApp(), processes: FakeProcesses = FakeProcesses()
  ) {
    config = InMemoryConfigStore(configured ? Config(url: Self.serverURL) : Config())
    secrets = InMemorySecretStore(token: configured ? "tk_secret" : nil)
    self.topics = ScriptedTopicSource(topics: topics, failingWith: topicFailure)
    self.app = app
    self.processes = processes
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
    return CLIEnvironment(
      paths: paths, variables: variables, terminal: terminal, executablePath: executablePath,
      config: config, secrets: secrets, app: app,
      topicSource: { _, _, _ in source }, processes: processes, releases: releases,
      prompter: prompter, readStandardInput: { input })
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
