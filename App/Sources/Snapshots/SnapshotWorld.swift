#if SNAPSHOT_HARNESS
  import Foundation
  import NtfyAppLogic
  import NtfyCore
  import NtfyPlatform
  import NtfyStore

  /// What differs between the worlds the snapshots are drawn from.
  struct SnapshotWorldOptions {
    var seeded = true
    /// The stream connects (the status reads "Connected") or fails (the status reads "Reconnecting").
    var connected = true
    var permission = NotificationPermission.allowed
    var meeting = MeetingState.inactive
    var composer = SnapshotPublisher.Mode.fail
    var config: @Sendable (inout Config, Date) -> Void = { _, _ in }

    /// The state a surface needs; the same world serves both appearances.
    init(for target: SnapshotSpec.Target) {
      switch target {
      case .popover(let scenario):
        switch scenario {
        case .empty: seeded = false
        case .messages, .hover: break
        case .pausedUntil:
          config = { config, now in config.pausedUntil = now.addingTimeInterval(95 * 60) }
        case .pausedIndefinitely:
          config = { config, _ in config.pausedUntil = PauseWindow.indefinite }
        case .meeting:
          meeting = .active(.app("Zoom"))
          config = { config, _ in config.meeting.mode = .pause }
        case .presenting:
          config = { config, now in config.meeting.presentingUntil = now.addingTimeInterval(40 * 60)
          }
        case .disconnected:
          connected = false
          permission = NotificationPermission(authorization: .denied)
        }
      case .history(let scenario):
        seeded = scenario != .empty
        composer = scenario == .sending ? .hang : .fail
      case .settings, .onboarding:
        break
      }
    }
  }

  /// Every model of the app over fakes and a history in a temp directory. Nothing in it touches
  /// the real config, Keychain, network, notification center, socket or login item.
  @MainActor
  struct SnapshotWorld {
    let directory: URL
    let windows = WindowRouter()
    let coordinator = WindowCoordinator { _ in }
    let app: AppModel
    let history: HistoryModel
    let settings: SettingsModel
    let onboarding: OnboardingModel
    private let supervisor: StreamSupervisor

    init(_ options: SnapshotWorldOptions, root: URL) async throws {
      let now = Date()
      directory = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

      let clock = SystemClock()
      var stored = Config(
        url: "https://ntfy.example.com", extraTopics: ["home", "ci", "alerts"],
        topicSettings: [
          "ci": TopicSettings(minPriority: 3, emoji: "🛠"),
          "home": TopicSettings(emoji: "🏠"),
          "alerts": TopicSettings(emoji: "🚨"),
        ])
      stored.sounds[3] = .named("Glass")
      stored.dismiss[2] = 6
      options.config(&stored, now)
      let config = FileConfigStore(url: directory.appending(path: "config.json"))
      try? await config.save(stored)

      let store = try SQLiteHistoryStore.open(
        at: directory.appending(path: "history.sqlite"), server: "https://ntfy.example.com",
        clock: clock)
      if options.seeded { try await Self.seed(store, now: now) }

      let delivery = DeliveryService(
        poster: SnapshotPoster(), history: store, inbox: store, config: config, clock: clock)
      let ports = StreamSupervisor.Ports(
        stream: SnapshotStream(connects: options.connected), poller: SnapshotPoller(),
        topics: SnapshotTopics(), cursor: SnapshotCursor(), history: store,
        delivery: SnapshotDelivery(), systemEvents: SnapshotSystemEvents(), clock: clock)
      supervisor = StreamSupervisor(ports: ports, options: StreamSupervisor.Options())
      let handles = PipelineHandles(
        store: store, delivery: delivery, supervisor: supervisor,
        attachments: SnapshotAttachments(directory: directory))
      let source = SnapshotSource(handles: handles)

      let permissions = SnapshotPermissions(permission: options.permission)
      let meeting = SnapshotMeeting(state: options.meeting)
      app = AppModel(
        source: source, meeting: meeting, config: config, permissions: permissions, clock: clock,
        configChanges: { AsyncStream { _ in } })
      history = HistoryModel(
        source: source, opener: SnapshotLinkOpener(), clock: clock, config: config)
      history.publisher = SnapshotPublisherProvider(mode: options.composer)
      let secrets = SnapshotSecrets(token: "tk_snapshot")
      let loginItem = SnapshotLoginItem(current: .enabled)
      func flow() -> NotificationPermissionFlow {
        NotificationPermissionFlow(
          permissions: permissions, opener: SnapshotSettingsOpener(),
          quitGuard: SnapshotQuitGuard(), source: source, clock: clock)
      }
      settings = SettingsModel(
        SettingsModel.Dependencies(
          config: config, secrets: secrets, tester: SnapshotServerTester(),
          topicSource: SnapshotTopics(), source: source, loginItem: loginItem,
          sounds: SnapshotSounds(), preview: SnapshotPreview(),
          configChanges: { AsyncStream { _ in } }),
        app: app, permission: flow(), windows: windows)
      onboarding = OnboardingModel(
        config: config, secrets: secrets, tester: SnapshotServerTester(), loginItem: loginItem,
        permission: flow())

      await supervisor.start()
      app.start()
      history.start()
      settings.start()
      await app.refreshPermission()
      await app.refresh()
      await history.refresh()
      await settings.reload()
    }

    func stop() async {
      app.stop()
      history.stop()
      settings.stop()
      await supervisor.stop()
    }

    /// Writes the fixtures through the store's own interface, then sets their read and
    /// acknowledged state.
    private static func seed(_ store: SQLiteHistoryStore, now: Date) async throws {
      for entry in SnapshotFixtures.entries(now: now) {
        let message = entry.message
        try await store.append(message)
        if entry.isRead { try await store.markRead(topic: message.topic, id: message.id) }
        if entry.isAcknowledged {
          try await store.acknowledge(topic: message.topic, id: message.id)
        }
      }
    }
  }

  /// The pipeline of the snapshot world; it never rebuilds.
  struct SnapshotSource: PipelineSource {
    let handles: PipelineHandles
    func current() async -> PipelineHandles? { handles }
    func rebuilds() -> AsyncStream<Void> { AsyncStream { _ in } }
  }
#endif
