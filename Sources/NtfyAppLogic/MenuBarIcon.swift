/// Which symbol the menu bar shows, most urgent state first.
public enum MenuBarIcon: Sendable, Hashable {
  case idle, unread, paused, offline, attention

  /// An SF Symbol name.
  public var symbolName: String {
    switch self {
    case .idle: "bell"
    case .unread: "bell.badge"
    case .paused: "bell.slash"
    case .offline: "wifi.slash"
    case .attention: "exclamationmark.triangle"
    }
  }
}
