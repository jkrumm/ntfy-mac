import Foundation
import Observation

/// The windows the app can show.
public enum AppWindow: String, Sendable, Hashable, CaseIterable {
  case history, settings, onboarding
}

/// Asks the UI to show a window, and which message the History window should select. Anyone on
/// the main actor (the notification click presenter, the second-launch handler) asks; the
/// SwiftUI side observes `request`, opens the window and calls `consume`.
@MainActor @Observable
public final class WindowRouter {
  public struct Request: Sendable, Hashable {
    public let window: AppWindow
    /// Distinguishes two requests for the same window, so each one is observed.
    public let serial: Int
  }

  /// The newest request nobody has consumed yet.
  public private(set) var request: Request?
  /// The message the History window should select when it appears; the window clears it with
  /// `takeSelection()` once it applied it.
  public private(set) var pendingSelection: MessageKey?
  @ObservationIgnored private var serial = 0

  public init() {}

  public func showHistory(selecting key: MessageKey? = nil) {
    if let key { pendingSelection = key }
    post(.history)
  }

  public func showSettings() { post(.settings) }

  public func showOnboarding() { post(.onboarding) }

  /// The window a reopen of the running app (Dock icon, Spotlight, Finder, Launchpad) asks for:
  /// none while one is already visible (it only comes to the front), History otherwise. Settings
  /// is never a reopen destination.
  public nonisolated static func reopenDestination(hasVisibleWindows: Bool) -> AppWindow? {
    hasVisibleWindows ? nil : .history
  }

  /// Handles a reopen; returns whether AppKit should do its default (front the visible windows).
  public func reopen(hasVisibleWindows: Bool) -> Bool {
    guard Self.reopenDestination(hasVisibleWindows: hasVisibleWindows) != nil else { return true }
    showHistory()
    return false
  }

  /// Marks `request` as handled; a newer request stays.
  public func consume(_ handled: Request) {
    if request == handled { request = nil }
  }

  /// Returns the pending selection and clears it.
  public func takeSelection() -> MessageKey? {
    defer { pendingSelection = nil }
    return pendingSelection
  }

  private func post(_ window: AppWindow) {
    serial += 1
    request = Request(window: window, serial: serial)
  }
}
