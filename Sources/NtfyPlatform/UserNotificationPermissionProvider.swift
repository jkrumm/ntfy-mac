import NtfyCore
import UserNotifications

/// `NotificationPermissionProviding` over the notification center.
///
/// The settings are always read in a call of their own, never from inside the authorization
/// completion (that one times out). The caller must keep the process alive while the prompt is
/// pending.
public struct UserNotificationPermissionProvider: NotificationPermissionProviding {
  private let center: any NotificationCenterClient

  public init(center: any NotificationCenterClient) {
    self.center = center
  }

  public func current() async -> NotificationPermission {
    NotificationPermission(await center.settings())
  }

  public func requestAuthorization() async -> NotificationPermission {
    _ = await center.requestAuthorization()
    return await current()
  }
}

extension NotificationPermission {
  public init(_ snapshot: NotificationSettingsSnapshot) {
    self.init(
      authorization: Self.authorization(snapshot.authorization),
      alertStyle: Self.alertStyle(snapshot.alertStyle), sound: Self.setting(snapshot.sound),
      badge: Self.setting(snapshot.badge),
      notificationCenter: Self.setting(snapshot.notificationCenter),
      lockScreen: Self.setting(snapshot.lockScreen),
      timeSensitive: Self.setting(snapshot.timeSensitive),
      scheduledSummary: Self.setting(snapshot.scheduledDelivery))
  }

  private static func authorization(_ status: UNAuthorizationStatus) -> Authorization {
    switch status {
    case .notDetermined: .notDetermined
    case .denied: .denied
    case .authorized: .authorized
    case .provisional: .provisional
    @unknown default: .notDetermined
    }
  }

  private static func alertStyle(_ style: UNAlertStyle) -> AlertStyle {
    switch style {
    case .none: .none
    case .banner: .banner
    case .alert: .alert
    @unknown default: .none
    }
  }

  private static func setting(_ setting: UNNotificationSetting) -> Setting {
    switch setting {
    case .enabled: .enabled
    case .disabled: .disabled
    case .notSupported: .notSupported
    @unknown default: .notSupported
    }
  }
}
