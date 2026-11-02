import Foundation
import NtfyCore
import UserNotifications

/// `NotificationCenterClient` over `UNUserNotificationCenter.current()`, which is looked up per
/// call: it aborts in a process without a bundle, so nothing touches it until a call is made.
public struct LiveNotificationCenter: NotificationCenterClient {
  private let log: @Sendable (String) -> Void

  public init(log: @escaping @Sendable (String) -> Void = { _ in }) {
    self.log = log
  }

  public func add(_ spec: UserNotificationSpec) async throws(NtfyError) {
    let request = UNNotificationRequest(
      identifier: spec.identifier, content: UserNotificationMapper.content(from: spec),
      trigger: nil)
    do {
      try await UNUserNotificationCenter.current().add(request)
    } catch {
      throw UserNotificationMapper.error(from: error)
    }
  }

  public func removeDelivered(identifiers: [String]) async {
    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
  }

  public func delivered() async -> [DeliveredNotification] {
    await UNUserNotificationCenter.current().deliveredNotifications().map { notification in
      let request = notification.request
      return DeliveredNotification(
        identifier: request.identifier, userInfo: Self.strings(request.content.userInfo))
    }
  }

  public func setCategories(_ categories: [NotificationCategorySpec]) async {
    UNUserNotificationCenter.current().setNotificationCategories(
      Set(categories.map(UserNotificationMapper.category(from:))))
  }

  public func settings() async -> NotificationSettingsSnapshot {
    NotificationSettingsSnapshot(await UNUserNotificationCenter.current().notificationSettings())
  }

  public func requestAuthorization() async -> Bool {
    do {
      return try await UNUserNotificationCenter.current().requestAuthorization(
        options: [.alert, .sound, .badge])
    } catch {
      log("authorization request failed: \(error.localizedDescription)")
      return false
    }
  }

  private static func strings(_ info: [AnyHashable: Any]) -> [String: String] {
    var result: [String: String] = [:]
    for (key, value) in info {
      if let key = key as? String, let value = value as? String { result[key] = value }
    }
    return result
  }
}

extension NotificationSettingsSnapshot {
  init(_ settings: UNNotificationSettings) {
    self.init(
      authorization: settings.authorizationStatus, alertStyle: settings.alertStyle,
      sound: settings.soundSetting, badge: settings.badgeSetting,
      notificationCenter: settings.notificationCenterSetting,
      lockScreen: settings.lockScreenSetting, timeSensitive: settings.timeSensitiveSetting,
      scheduledDelivery: settings.scheduledDeliverySetting)
  }
}
