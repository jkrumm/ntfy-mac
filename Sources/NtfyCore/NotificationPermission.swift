/// What the system lets this app do with notifications, as far as it can tell.
public struct NotificationPermission: Sendable, Hashable, Codable {
  public enum Authorization: String, Sendable, Hashable, Codable {
    case notDetermined, denied, authorized, provisional, ephemeral
  }

  public enum AlertStyle: String, Sendable, Hashable, Codable {
    case none, banner, alert
  }

  public enum Setting: String, Sendable, Hashable, Codable {
    case enabled, disabled, notSupported
  }

  public var authorization: Authorization
  public var alertStyle: AlertStyle
  public var sound: Setting
  public var badge: Setting
  public var notificationCenter: Setting
  public var lockScreen: Setting
  public var timeSensitive: Setting
  /// The user routes this app into the Scheduled Summary: notifications arrive once a day.
  public var scheduledSummary: Setting

  public init(
    authorization: Authorization, alertStyle: AlertStyle = .banner, sound: Setting = .enabled,
    badge: Setting = .enabled, notificationCenter: Setting = .enabled,
    lockScreen: Setting = .enabled, timeSensitive: Setting = .enabled,
    scheduledSummary: Setting = .disabled
  ) {
    self.authorization = authorization
    self.alertStyle = alertStyle
    self.sound = sound
    self.badge = badge
    self.notificationCenter = notificationCenter
    self.lockScreen = lockScreen
    self.timeSensitive = timeSensitive
    self.scheduledSummary = scheduledSummary
  }

  /// Everything on, as after the user allowed notifications.
  public static let allowed = NotificationPermission(authorization: .authorized)

  private var mayPost: Bool { authorization == .authorized || authorization == .provisional }

  /// Notifications can reach the user at all: allowed, and shown as an alert or kept in the
  /// Notification Center.
  public var isUsable: Bool {
    mayPost && (alertStyle != .none || notificationCenter == .enabled)
  }

  /// What keeps notifications from working as intended, most severe first.
  public var problems: [PermissionProblem] {
    switch authorization {
    case .notDetermined: return [.notDetermined]
    case .denied: return [.denied]
    case .authorized, .provisional, .ephemeral: break
    }
    var result: [PermissionProblem] = []
    if alertStyle == .none { result.append(.alertsOff) }
    if scheduledSummary == .enabled { result.append(.scheduledSummary) }
    if timeSensitive == .disabled { result.append(.timeSensitiveOff) }
    if sound == .disabled { result.append(.soundOff) }
    return result
  }
}

/// One reason notifications are not as the user expects, with a stable code for scripts.
public struct PermissionProblem: Sendable, Hashable, Codable {
  public let code: String
  public let hint: String

  public init(code: String, hint: String) {
    self.code = code
    self.hint = hint
  }

  public static let notDetermined = PermissionProblem(
    code: "not-determined", hint: "Notifications have not been allowed yet; allow them when asked")
  public static let denied = PermissionProblem(
    code: "denied", hint: "Allow notifications for ntfy-mac in System Settings > Notifications")
  public static let alertsOff = PermissionProblem(
    code: "alerts-off",
    hint: "Banners and alerts are off; choose Banners or Alerts for ntfy-mac in System Settings")
  public static let scheduledSummary = PermissionProblem(
    code: "scheduled-summary",
    hint: "Notifications are delivered in a daily summary; turn off Scheduled Summary for ntfy-mac")
  public static let timeSensitiveOff = PermissionProblem(
    code: "time-sensitive-off", hint: "Urgent messages will not break through Focus")
  public static let soundOff = PermissionProblem(code: "sound-off", hint: "No sound will play")
}

/// Reads and requests the notification permission of the app (UserNotifications in production).
public protocol NotificationPermissionProviding: Sendable {
  func current() async -> NotificationPermission
  /// Shows the system prompt when the state is not determined, then returns the new state.
  func requestAuthorization() async -> NotificationPermission
}
