import NtfyCore

/// The sections of the Settings window and the catalog settings each one shows. The window is
/// built from this list, and `SettingsModel.exposedSettings` is derived from it, so a setting the
/// UI shows is always one the catalog (and so the CLI) has.
public enum SettingsSection: String, Sendable, CaseIterable, Identifiable {
  case server, topics, sounds, reAlert, quietHours, actions, general

  public var id: String { rawValue }

  public var title: String {
    switch self {
    case .server: "Server"
    case .topics: "Topics"
    case .sounds: "Sounds & dismiss"
    case .reAlert: "Re-alert"
    case .quietHours: "Quiet hours"
    case .actions: "Actions safety"
    case .general: "General"
    }
  }

  public var symbol: String {
    switch self {
    case .server: "server.rack"
    case .topics: "number"
    case .sounds: "speaker.wave.2"
    case .reAlert: "bell.badge"
    case .quietHours: "moon"
    case .actions: "lock.shield"
    case .general: "gearshape"
    }
  }

  /// The settings this section edits. The sound list, the sound preview and the notification
  /// permission are catalog entries too, but the window shows them as the sound picker's
  /// options, a button and a status, not as settings of their own.
  public var settings: [SettingID] {
    switch self {
    case .server: [.serverURL, .token, .allowInsecure]
    case .topics: [.topicSubscribe, .topicUnsubscribe, .topicMute, .topicMinPriority, .topicEmoji]
    case .sounds: [.sounds, .dismiss]
    case .reAlert: [.reAlert, .reAlertIntervalSeconds, .reAlertMinPriority, .reAlertMaxRepeats]
    case .quietHours:
      [
        .quietHoursEnabled, .quietHoursStart, .quietHoursEnd, .quietHoursUrgentBypass,
        .quietHoursDigest,
      ]
    case .actions: [.allowPrivateNetworkActions]
    case .general: [.loginItem, .pause]
    }
  }
}

/// A row label from the catalog, so the window and the docs name a setting the same way.
public func settingLabel(_ id: SettingID) -> String { SettingsCatalog.entry(id).label }

/// The command that does the same from a terminal, for a tooltip.
public func settingCommandHint(_ id: SettingID) -> String {
  SettingsCatalog.entry(id).example.map { "Terminal: \($0)" } ?? ""
}
