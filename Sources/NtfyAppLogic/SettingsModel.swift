import Foundation
import NtfyCore
import Observation

/// What the Settings window shows and does. Every change is written to the config at once,
/// through `ConfigStore.update` (the file the CLI edits; the running app picks it up through its
/// config watcher). The exception is the server address and token: they are tested first and
/// saved together (`testAndSave`), the token to the Keychain only.
///
/// The model keeps a snapshot of the config for the views, applies each change to it before the
/// write finishes, and reloads when the file changes under it (a `ntfy-mac config set` from a
/// terminal). Everything is plain values; views read the properties and call the actions.
@MainActor @Observable
public final class SettingsModel {
  // MARK: State

  /// The config as last read or edited.
  public private(set) var config = Config()
  public private(set) var hasStoredToken = false
  public private(set) var loginItem = LoginItemState.notRegistered
  /// The topics the account has on the server; empty until fetched, or without a server.
  public private(set) var serverTopics: [String] = []
  /// Topics with messages in the history.
  public private(set) var historyTopics: [String] = []
  public private(set) var soundNames: [String] = []
  public private(set) var serverTest = ServerTestState.idle
  /// The last thing that went wrong, in a sentence; cleared by the next change that works.
  public private(set) var notice: String?

  /// The server address as typed. Follows the saved one until it is edited; unsaved edits survive reloads.
  public var urlText = ""
  /// The token as typed. Empty means "keep the stored one"; it is never filled from the Keychain.
  public var tokenText = ""
  public var newTopicText = ""

  public let permission: NotificationPermissionFlow
  public let app: AppModel

  @ObservationIgnored let store: any ConfigStore
  @ObservationIgnored let connection: ServerConnection
  @ObservationIgnored let secrets: any SecretStore
  @ObservationIgnored let topicSource: any TopicSource
  @ObservationIgnored let source: any PipelineSource
  @ObservationIgnored let loginItems: any LoginItemControlling
  @ObservationIgnored let sounds: any SoundListing
  @ObservationIgnored let preview: any SoundPreviewing
  @ObservationIgnored let windows: WindowRouter
  @ObservationIgnored let configChanges: @Sendable () -> AsyncStream<Void>
  @ObservationIgnored let calendar: Calendar
  @ObservationIgnored let log: @Sendable (String) -> Void
  @ObservationIgnored private var tasks: [Task<Void, Never>] = []
  /// The tail of the config work (writes and reloads), which runs one after the other.
  @ObservationIgnored private var lastConfigWork: Task<Void, Never>?
  /// Counts optimistic edits; a load that started before one must not overwrite it.
  @ObservationIgnored private var editGeneration = 0

  public struct Dependencies {
    public var config: any ConfigStore
    public var secrets: any SecretStore
    public var tester: any ServerTesting
    public var topicSource: any TopicSource
    public var source: any PipelineSource
    public var loginItem: any LoginItemControlling
    public var sounds: any SoundListing
    public var preview: any SoundPreviewing
    public var configChanges: @Sendable () -> AsyncStream<Void>

    public init(
      config: any ConfigStore, secrets: any SecretStore, tester: any ServerTesting,
      topicSource: any TopicSource, source: any PipelineSource,
      loginItem: any LoginItemControlling, sounds: any SoundListing,
      preview: any SoundPreviewing, configChanges: @escaping @Sendable () -> AsyncStream<Void>
    ) {
      self.config = config
      self.secrets = secrets
      self.tester = tester
      self.topicSource = topicSource
      self.source = source
      self.loginItem = loginItem
      self.sounds = sounds
      self.preview = preview
      self.configChanges = configChanges
    }
  }

  public init(
    _ dependencies: Dependencies, app: AppModel, permission: NotificationPermissionFlow,
    windows: WindowRouter, calendar: Calendar = .current,
    log: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    store = dependencies.config
    secrets = dependencies.secrets
    connection = ServerConnection(
      config: dependencies.config, secrets: dependencies.secrets, tester: dependencies.tester)
    topicSource = dependencies.topicSource
    source = dependencies.source
    loginItems = dependencies.loginItem
    sounds = dependencies.sounds
    preview = dependencies.preview
    configChanges = dependencies.configChanges
    self.app = app
    self.permission = permission
    self.windows = windows
    self.calendar = calendar
    self.log = log
  }

  // MARK: Derived

  /// Every catalog setting the window edits, collected from its sections. Sound list, sound
  /// preview and the notification permission are shown differently; see `SettingsSection`.
  public var exposedSettings: [SettingID] { SettingsSection.allCases.flatMap(\.settings) }

  public var appVersion: String { Version.current }

  public var maskedTokenPlaceholder: String {
    hasStoredToken ? "Saved in the Keychain" : "tk_..."
  }

  /// The typed address or token differs from what is saved.
  public var hasUnsavedServerChanges: Bool {
    !tokenText.isEmpty || urlText != (config.url ?? "")
  }

  public var loginItemNote: String? {
    switch loginItem {
    case .requiresApproval: "Approve ntfy-mac in System Settings, General, Login Items."
    case .notFound: "macOS does not know this app as a login item; run it from Applications."
    case .enabled, .notRegistered: nil
    }
  }

  // MARK: Lifecycle

  /// Reads everything, then follows the config file. Idempotent.
  public func start() {
    guard tasks.isEmpty else { return }
    let changes = configChanges()
    tasks = [
      Task {
        await reload()
        await reloadServerTopics()
      },
      Task {
        for await _ in changes { await reloadConfig() }
      },
      Task { await permission.refresh() },
    ]
  }

  public func stop() {
    for task in tasks { task.cancel() }
    tasks = []
  }

  /// Re-reads the config, the login item, the sound list and the topics seen in the history.
  public func reload() async {
    await reloadConfig()
    soundNames = sounds.names()
    do throws(NtfyError) {
      historyTopics = try await source.current()?.inbox.topics().map(\.topic) ?? []
    } catch {
      log("history topics not read: \(error)")
    }
  }

  /// Calls run one after the other, like `AppModel.refresh`, so a late load never overwrites a
  /// newer one.
  func reloadConfig() async {
    await serialized { await self.loadConfig() }
  }

  private func serialized(_ work: @escaping @MainActor () async -> Void) async {
    let previous = lastConfigWork
    let run = Task {
      await previous?.value
      await work()
    }
    lastConfigWork = run
    await run.value
  }

  private func loadConfig() async {
    let previousURL = config.url ?? ""
    defer { if urlText == previousURL { urlText = config.url ?? "" } }
    let generation = editGeneration
    do throws(NtfyError) {
      let loaded = try await store.load()
      // An edit made while this load ran is newer than the file; its own write reloads next.
      if generation == editGeneration { config = loaded }
    } catch {
      log("config not read: \(error)")
    }
    hasStoredToken = ((try? await secrets.token()) ?? nil).map { !$0.isEmpty } ?? false
    loginItem = loginItems.state()
  }

  /// Asks the server for the account's topics again.
  public func reloadServerTopics() async {
    guard config.url != nil else {
      serverTopics = []
      return
    }
    do throws(NtfyError) {
      serverTopics = try await topicSource.subscribedTopics()
    } catch {
      log("server topics not read: \(error)")
    }
  }

  // MARK: Writing

  /// Applies `change` to the snapshot, then to the file as one read-modify-write.
  func write(_ change: @escaping @Sendable (inout Config) -> Void) async {
    change(&config)
    editGeneration += 1
    await serialized {
      do throws(NtfyError) {
        try await self.store.update(change)
        self.notice = nil
      } catch {
        self.notice = "The setting could not be saved: \(error)"
        self.log("config not written: \(error)")
      }
      await self.loadConfig()
    }
  }

  func refuse(_ message: String) {
    notice = message
  }

  // MARK: Server

  public func setAllowInsecure(_ allow: Bool) async {
    await write { $0.allowInsecure = allow }
  }

  /// Tests the typed address and token; saves both only if the server accepts them.
  public func testAndSave() async {
    guard !serverTest.isTesting else { return }
    serverTest = .testing
    let result = await connection.testAndSave(urlText: urlText, tokenText: tokenText)
    serverTest = .finished(result)
    guard case .ok(let topics) = result else { return }
    tokenText = ""
    serverTopics = topics
    await reloadConfig()
    urlText = config.url ?? urlText
  }

  // MARK: Actions safety

  public func setAllowPrivateNetworkActions(_ allow: Bool) async {
    await write { $0.allowPrivateNetworkActions = allow }
  }

  // MARK: General

  public func setLaunchAtLogin(_ enabled: Bool) async {
    do throws(NtfyError) {
      loginItem = try loginItems.setEnabled(enabled)
      notice = nil
    } catch {
      notice = "The login item could not be changed: \(error)"
    }
  }

  /// Ends a pause and shows what was held back.
  public func resume() async {
    await app.resume()
    await reloadConfig()
  }

  /// Opens the onboarding window again.
  public func setUpAgain() {
    windows.showOnboarding()
  }
}
