import NtfyAppLogic

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
