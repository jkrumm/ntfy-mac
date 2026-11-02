import Foundation
import NtfyCore

/// The sounds that can be chosen, by name. The names come from the same directories the CLI's
/// `config sounds list` reads.
public protocol SoundListing: Sendable {
  func names() -> [String]
}

/// Plays a system sound once. UI only: it is the one catalog entry the CLI does not have.
@MainActor
public protocol SoundPreviewing: Sendable {
  func play(_ name: String)
}

/// Opens a System Settings URL (`x-apple.systempreferences:`).
public protocol SystemSettingsOpening: Sendable {
  /// `false` when nothing could open the URL.
  func open(_ url: URL) async -> Bool
}

/// Keeps the process from quitting while the system asks the user something. The returned closure
/// ends the hold.
public protocol QuitGuarding: Sendable {
  func hold(reason: String) -> @Sendable () -> Void
}

/// The deep link to the notification settings of this app, and the fallback.
public struct NotificationSettingsLink: Sendable {
  public static let appPane = URL(
    string:
      "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.jkrumm.ntfy-mac"
  )
  public static let pane = URL(
    string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")

  private let opener: any SystemSettingsOpening

  public init(opener: any SystemSettingsOpening) { self.opener = opener }

  /// Opens the pane of this app; the `id=` part is undocumented, so a failure falls back to the
  /// Notifications pane. `false` when neither opened.
  @discardableResult
  public func open() async -> Bool {
    if let appPane = Self.appPane, await opener.open(appPane) { return true }
    guard let pane = Self.pane else { return false }
    return await opener.open(pane)
  }
}
