import AppKit
import NtfyAppLogic
import SwiftUI

/// Opens our windows from an accessory app and keeps the Dock icon honest: the app is a regular
/// (Dock) app while one of its windows is open, and an accessory again when the last one closes.
///
/// `openWindow` only exists inside SwiftUI, so a view hands it over once with `install`; anyone
/// who wants a window before that gets it as soon as it arrives. Requests from outside SwiftUI
/// (a notification click, a second launch) come through `WindowRouter`; a view calls `fulfil`
/// when the router's request changes.
@MainActor
final class WindowCoordinator {
  private var opener: OpenWindowAction?
  private var queued: [AppWindow] = []
  private var closing: Task<Void, Never>?
  private let onClose: (AppWindow) -> Void

  /// `onClose` is called with each of our windows that closes.
  init(onClose: @escaping (AppWindow) -> Void) {
    self.onClose = onClose
    closing = Task { [weak self] in
      let closes = NotificationCenter.default.notifications(named: NSWindow.willCloseNotification)
      for await note in closes {
        let window = note.object as? NSWindow
        self?.willClose(window)
      }
    }
  }

  deinit { closing?.cancel() }

  /// Remembers `openWindow`, and opens what was asked for before it was known.
  func install(_ openWindow: OpenWindowAction) {
    opener = openWindow
    let waiting = queued
    queued = []
    for window in waiting { show(window) }
  }

  /// Takes the router's pending request, if any, and shows its window.
  func fulfil(_ router: WindowRouter) {
    guard let request = router.request else { return }
    router.consume(request)
    show(request.window)
  }

  func show(_ window: AppWindow) {
    guard let opener else {
      queued.append(window)
      return
    }
    NSApp.setActivationPolicy(.regular)
    NSApp.activate()
    opener(id: window.rawValue)
    Task { await front(window) }
  }

  /// The window is created after `openWindow` returns, so wait for it briefly, then bring it to
  /// the front and make it key.
  private func front(_ window: AppWindow) async {
    for _ in 0..<20 {
      if let found = NSApp.windows.first(where: { appWindow(for: $0) == window }) {
        found.orderFrontRegardless()
        found.makeKey()
        return
      }
      try? await Task.sleep(for: .milliseconds(50))
    }
  }

  private func appWindow(for window: NSWindow) -> AppWindow? {
    AppWindow.allCases.first {
      $0.rawValue == window.identifier?.rawValue || $0.title == window.title
    }
  }

  private func willClose(_ window: NSWindow?) {
    guard let window, let closed = appWindow(for: window) else { return }
    onClose(closed)
    let othersOpen = NSApp.windows.contains {
      $0 !== window && $0.isVisible && appWindow(for: $0) != nil
    }
    if !othersOpen { NSApp.setActivationPolicy(.accessory) }
  }
}
