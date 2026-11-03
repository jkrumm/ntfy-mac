#if SNAPSHOT_HARNESS
  import AppKit
  import Foundation
  import NtfyAppLogic
  import NtfyCore
  import Synchronization

  // In-memory stand-ins for every port the models touch, so the snapshot build never reaches the
  // real config, Keychain, network, notification center, socket or login item.

  actor SnapshotSecrets: SecretStore {
    private var stored: String?
    init(token: String?) { stored = token }
    func token() -> String? { stored }
    func setToken(_ token: String) { stored = token }
    func deleteToken() { stored = nil }
  }

  struct SnapshotServerTester: ServerTesting {
    func test(url: String, token: String, allowInsecure: Bool) async -> ServerTestResult {
      .ok(topics: ["home", "ci", "alerts"])
    }
  }

  struct SnapshotTopics: TopicSource {
    func subscribedTopics() async throws(NtfyError) -> [String] { ["home", "ci", "alerts"] }
  }

  struct SnapshotLoginItem: LoginItemControlling {
    let current: LoginItemState
    func state() -> LoginItemState { current }
    func setEnabled(_ enabled: Bool) throws(NtfyError) -> LoginItemState { current }
  }

  struct SnapshotSounds: SoundListing {
    func names() -> [String] {
      ["Basso", "Blow", "Bottle", "Frog", "Funk", "Glass", "Hero", "Morse", "Ping", "Pop"]
    }
  }

  /// Never plays: a snapshot must not make a sound.
  struct SnapshotPreview: SoundPreviewing {
    func play(_ name: String) {}
  }

  struct SnapshotPermissions: NotificationPermissionProviding {
    let permission: NotificationPermission
    func current() async -> NotificationPermission { permission }
    func requestAuthorization() async -> NotificationPermission { permission }
  }

  struct SnapshotSettingsOpener: SystemSettingsOpening {
    func open(_ url: URL) async -> Bool { false }
  }

  struct SnapshotQuitGuard: QuitGuarding {
    func hold(reason: String) -> @Sendable () -> Void { {} }
  }

  struct SnapshotLinkOpener: LinkOpening {
    func open(_ url: URL) async -> Bool { false }
  }

  struct SnapshotMeeting: MeetingStateProviding {
    let state: MeetingState
    func current() async -> MeetingState { state }
    func hasReading() async -> Bool { true }
    func changes() -> AsyncStream<MeetingState> {
      AsyncStream { continuation in
        continuation.yield(state)
        continuation.onTermination = { _ in }
      }
    }
  }

  /// Posts nothing and shows nothing.
  struct SnapshotPoster: NotificationPoster {
    func post(_ content: NotificationContent) async throws(NtfyError) {}
    func postMissedSummary(count: Int, oldestTopic: String, cause: MissedSummaryCause)
      async throws(NtfyError)
    {}
    func remove(identifiers: [String]) async {}
    func deliveredIdentifiers() async -> Set<String> { [] }
  }

  /// A publisher that either never answers (the composer shows "sending") or fails.
  struct SnapshotPublisher: NtfyPublishing {
    enum Mode: Sendable { case hang, fail }
    let mode: Mode

    func publish(_ request: PublishRequest) async throws(NtfyError) -> PublishedMessage {
      switch mode {
      case .hang:
        try? await Task.sleep(for: .seconds(3600))
        throw .serverUnreachable
      case .fail:
        throw .serverUnreachable
      }
    }
  }

  struct SnapshotPublisherProvider: PublisherProviding {
    let mode: SnapshotPublisher.Mode
    func resolve() async throws(NtfyError) -> PublisherResolution {
      .ready(SnapshotPublisher(mode: mode))
    }
  }

  // MARK: Stream

  /// A stream that connects and stays open, or fails every time, like an unreachable server.
  struct SnapshotStream: MessageStream {
    let connects: Bool

    func events(topics: [String], since: String?) -> AsyncThrowingStream<StreamEvent, any Error> {
      AsyncThrowingStream { continuation in
        guard connects else {
          continuation.finish(throwing: NtfyError.serverUnreachable)
          return
        }
        continuation.yield(.open)
      }
    }
  }

  struct SnapshotPoller: MessagePoller {
    func poll(topics: [String], since: String?) async throws(NtfyError) -> [NtfyMessage] { [] }
  }

  actor SnapshotCursor: CursorStore {
    private var cursor: String?
    func load() -> String? { cursor }
    func save(_ id: String) { cursor = id }
  }

  struct SnapshotDelivery: Delivering {
    func deliver(_ message: NtfyMessage) async {}
    func announceMissed(_ messages: [NtfyMessage]) async {}
    func withdraw(topic: String, sequenceID: String) async {}
    func clear(topic: String, sequenceID: String) async {}
  }

  struct SnapshotSystemEvents: SystemEvents {
    func events() -> AsyncStream<SystemEvent> { AsyncStream { _ in } }
  }

  // MARK: Attachments

  /// "Downloads" a generated chart image into the snapshot's temp directory.
  struct SnapshotAttachments: AttachmentFetching {
    let directory: URL

    func fetch(_ attachment: MessageAttachment) async throws(NtfyError) -> URL {
      let file = directory.appending(path: "attachment.png")
      if !FileManager.default.fileExists(atPath: file.path) {
        guard let data = await SnapshotChart.pngData() else { throw .invalidResponse("no image") }
        try? data.write(to: file)
      }
      return file
    }
  }

  enum SnapshotChart {
    /// A small line chart on a dark panel, so an image attachment looks like one.
    @MainActor
    static func pngData() -> Data? {
      let size = NSSize(width: 640, height: 320)
      let image = NSImage(size: size, flipped: false) { rect in
        NSColor(calibratedRed: 0.11, green: 0.13, blue: 0.17, alpha: 1).setFill()
        rect.fill()
        let line = NSBezierPath()
        let points: [CGFloat] = [0.2, 0.25, 0.22, 0.4, 0.38, 0.55, 0.6, 0.72, 0.8, 0.93]
        for (index, value) in points.enumerated() {
          let point = NSPoint(
            x: 30 + CGFloat(index) * (rect.width - 60) / CGFloat(points.count - 1),
            y: 30 + value * (rect.height - 60))
          index == 0 ? line.move(to: point) : line.line(to: point)
        }
        NSColor.systemOrange.setStroke()
        line.lineWidth = 4
        line.stroke()
        return true
      }
      guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else {
        return nil
      }
      return rep.representation(using: .png, properties: [:])
    }
  }
#endif
