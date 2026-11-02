import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Synchronization

struct StubSoundList: SoundListing {
  var list = ["Glass", "Ping", "Pop", "Sosumi", "Tink"]
  func names() -> [String] { list }
}

@MainActor
final class RecordingSoundPreview: SoundPreviewing {
  private(set) var played: [String] = []
  func play(_ name: String) { played.append(name) }
}

/// Opens nothing; says yes to the URLs in `accepts` (all of them by default).
final class RecordingOpener: SystemSettingsOpening {
  private let state = Mutex<[URL]>([])
  private let accepted: @Sendable (URL) -> Bool

  init(accepts: @escaping @Sendable (URL) -> Bool = { _ in true }) { accepted = accepts }

  var opened: [URL] { state.withLock { $0 } }

  func open(_ url: URL) async -> Bool {
    state.withLock { $0.append(url) }
    return accepted(url)
  }
}

final class RecordingQuitGuard: QuitGuarding {
  private let state = Mutex((holds: 0, releases: 0))

  var holds: Int { state.withLock { $0.holds } }
  var releases: Int { state.withLock { $0.releases } }

  func hold(reason: String) -> @Sendable () -> Void {
    state.withLock { $0.holds += 1 }
    return { [self] in state.withLock { $0.releases += 1 } }
  }
}

/// A scratch directory for a real `config.json`.
final class SettingsScratch: Sendable {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("ntfy-mac-settings-\(UUID().uuidString)", isDirectory: true)

  var file: URL { directory.appendingPathComponent("config.json") }

  init() {
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  }
  deinit { try? FileManager.default.removeItem(at: directory) }

  func write(_ json: String) throws { try Data(json.utf8).write(to: file) }

  func object() throws -> [String: ConfigValue] {
    let data = try Data(contentsOf: file)
    guard let object = ConfigValue.parseObject(data) else { return [:] }
    return object
  }
}

/// The settings model over fakes. `store` is the file the model writes; pass a `FileConfigStore`
/// for a round trip through disk.
@MainActor
struct SettingsRig {
  let store: any ConfigStore
  let secrets: InMemorySecretStore
  let tester: ScriptedServerTester
  let topics: ScriptedTopicSource
  let loginItem: InMemoryLoginItem
  let preview = RecordingSoundPreview()
  let opener = RecordingOpener()
  let quitGuard = RecordingQuitGuard()
  let permissionProvider: InMemoryNotificationPermission
  let windows = WindowRouter()
  let configChanges = ChangeSignal()
  let pipeline: PipelineFixture
  let source = ManualPipelineSource()
  let app: AppModel
  let model: SettingsModel

  init(
    store: (any ConfigStore)? = nil, token: String? = nil, serverTopics: [String] = [],
    testResult: ServerTestResult = .ok(topics: []), permission: NotificationPermission = .allowed,
    loginItem: InMemoryLoginItem = InMemoryLoginItem()
  ) {
    pipeline = PipelineFixture()
    source.set(pipeline.handles)
    let store = store ?? InMemoryConfigStore()
    self.store = store
    secrets = InMemorySecretStore(token: token)
    tester = ScriptedServerTester(testResult)
    topics = ScriptedTopicSource(topics: serverTopics)
    self.loginItem = loginItem
    permissionProvider = InMemoryNotificationPermission(permission)
    let signal = configChanges
    app = AppModel(
      source: source, meeting: ManualMeetingState(), config: store,
      permissions: permissionProvider, clock: pipeline.clock,
      configChanges: { signal.stream() })
    let flow = NotificationPermissionFlow(
      permissions: permissionProvider, opener: opener, quitGuard: quitGuard, source: source,
      clock: pipeline.clock)
    model = SettingsModel(
      SettingsModel.Dependencies(
        config: store, secrets: secrets, tester: tester, topicSource: topics, source: source,
        loginItem: loginItem, sounds: StubSoundList(), preview: preview,
        configChanges: { signal.stream() }),
      app: app, permission: flow, windows: windows,
      calendar: Calendar(identifier: .gregorian))
  }

  func edit(_ change: @escaping @Sendable (inout Config) -> Void) async {
    try? await store.update(change)
  }

  func replace(_ config: Config) async {
    try? await store.save(config)
  }

  var current: Config {
    get async { await ((try? store.load()) ?? Config()) }
  }

  /// Polls `condition` between yields, up to a hard cap.
  func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200_000 {
      if condition() { return true }
      await Task.yield()
    }
    return false
  }
}
