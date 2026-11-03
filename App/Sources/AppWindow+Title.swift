import NtfyAppLogic
import SwiftUI

extension AppWindow {
  /// The window title; also how the coordinator recognises our windows.
  var title: String {
    switch self {
    case .history: "History"
    case .settings: "Settings"
    case .onboarding: "Welcome to ntfy-mac"
    }
  }
}

extension Scene {
  /// The scene's default size from the window's metrics.
  func defaultSize(_ size: WindowSize) -> some Scene {
    defaultSize(width: CGFloat(size.width), height: CGFloat(size.height))
  }
}
