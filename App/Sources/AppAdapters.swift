import AppKit
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

/// Stands in for the history window until Wave 5: brings the app forward and logs the request.
struct ActivatingHistoryPresenter: HistoryPresenting {
  private let log = Log.logger(.delivery)

  func show(topic: String, id: String) async {
    log.info("history requested for \(topic, privacy: .private)/\(id, privacy: .private)")
    await MainActor.run { NSApp.activate() }
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
