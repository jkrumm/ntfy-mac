import AppKit
import NtfyAppLogic
import NtfyClient
import NtfyCore
import NtfyPlatform
import OSLog

/// Opens links with the user's default handler.
struct WorkspaceLinkOpener: LinkOpening {
  func open(_ url: URL) async -> Bool {
    await MainActor.run { NSWorkspace.shared.open(url) }
  }
}

/// Asks before a risky `http` action runs.
struct AlertConfirmer: ActionConfirming {
  func confirm(_ reason: String, action label: String) async -> Bool {
    await MainActor.run {
      NSApp.activate()
      let alert = NSAlert()
      alert.messageText = "Run \u{201C}\(label)\u{201D}?"
      alert.informativeText = reason
      alert.addButton(withTitle: "Run")
      alert.addButton(withTitle: "Cancel")
      return alert.runModal() == .alertFirstButtonReturn
    }
  }
}

/// Opens the History window with the message selected.
struct RoutedHistoryPresenter: HistoryPresenting {
  let windows: WindowRouter
  private let log = Log.logger(.interface)

  init(windows: WindowRouter) { self.windows = windows }

  func show(topic: String, id: String) async {
    log.info("history requested for \(topic, privacy: .private)/\(id, privacy: .private)")
    await windows.showHistory(selecting: MessageKey(topic: topic, id: id))
  }
}

/// Keeps App Nap away while the stream runs. The token is opaque and only handed back to
/// `endActivity`, so sharing it across threads is safe.
final class ProcessActivity: @unchecked Sendable {
  private let token: any NSObjectProtocol

  init(options: ProcessInfo.ActivityOptions, reason: String) {
    token = ProcessInfo.processInfo.beginActivity(options: options, reason: reason)
  }

  func end() { ProcessInfo.processInfo.endActivity(token) }
}

/// Fetches nothing: the local pipeline has no server to fetch from.
struct NoImageFetcher: ImageFetching {
  func fetch(_ url: URL) async -> URL? { nil }
}

/// Fetches nothing: the local pipeline has no server to fetch from.
struct NoAttachmentFetcher: AttachmentFetching {
  func fetch(_ attachment: MessageAttachment) async throws(NtfyError) -> URL {
    throw .invalidResponse("There is no server to download attachments from.")
  }
}

/// Opens System Settings URLs with the workspace.
extension WorkspaceLinkOpener: SystemSettingsOpening {}

/// The sounds on this Mac, from the same directories the CLI lists.
struct SystemSoundList: SoundListing {
  func names() -> [String] {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return SoundCatalog.sounds(in: SoundCatalog.directories(home: home)).map(\.name)
  }
}

/// Plays a system sound by name.
@MainActor
struct NSSoundPreview: SoundPreviewing {
  func play(_ name: String) {
    NSSound(named: NSSound.Name(name))?.play()
  }
}

/// Keeps the process from quitting while the system prompt is open.
struct ProcessQuitGuard: QuitGuarding {
  func hold(reason: String) -> @Sendable () -> Void {
    let activity = ProcessActivity(
      options: [.automaticTerminationDisabled, .suddenTerminationDisabled], reason: reason)
    return { activity.end() }
  }
}

/// The account's topics for whatever server the config and the Keychain hold now. Without a
/// server or a token there is nothing to ask and the list is empty.
struct ConfiguredTopicSource: TopicSource {
  let config: any ConfigStore
  let secrets: any SecretStore

  func subscribedTopics() async throws(NtfyError) -> [String] {
    let stored = try await config.load()
    guard let address = stored.url, let base = try? ServerAddress.parse(address),
      let token = try await secrets.token(), !token.isEmpty
    else { return [] }
    return try await NtfyAccountClient(
      base: base, token: token, allowInsecure: stored.allowInsecure
    ).subscribedTopics()
  }
}

/// Brings another running copy of this bundle id (the direct copy or the cask copy) forward.
struct RunningCopyActivator: RunningInstanceActivating {
  let bundleIdentifier: String

  func activateOther() -> Bool {
    let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
      .filter { $0.processIdentifier != getpid() && !$0.isTerminated }
    others.first?.activate()
    return !others.isEmpty
  }
}
