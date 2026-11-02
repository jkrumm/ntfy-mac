import Foundation
import NtfyCore
import UserNotifications

/// One button of a notification category.
public struct NotificationActionSpec: Sendable, Hashable {
  public let id: String
  public let title: String

  public init(id: String, title: String) {
    self.id = id
    self.title = title
  }
}

/// The buttons shown on notifications that carry this category.
public struct NotificationCategorySpec: Sendable, Hashable {
  public let identifier: String
  public let actions: [NotificationActionSpec]

  public init(identifier: String, actions: [NotificationActionSpec]) {
    self.identifier = identifier
    self.actions = actions
  }
}

/// A notification as the center is asked to show it, free of UserNotifications objects (which
/// are not `Sendable`). `UserNotificationMapper` turns it into the real thing.
public struct UserNotificationSpec: Sendable, Hashable {
  public let identifier: String
  public let title: String
  public let subtitle: String
  public let body: String
  public let threadID: String?
  /// System sound name; nil plays none.
  public let sound: String?
  public let interruption: InterruptionLevel
  public let relevance: Double
  /// Only the keys of `UserNotificationMapper`; never URLs or tokens.
  public let userInfo: [String: String]
  public let category: NotificationCategorySpec?
  /// A local image file to attach.
  public let attachment: URL?

  public init(
    identifier: String, title: String, subtitle: String, body: String, threadID: String?,
    sound: String?, interruption: InterruptionLevel, relevance: Double,
    userInfo: [String: String], category: NotificationCategorySpec?, attachment: URL?
  ) {
    self.identifier = identifier
    self.title = title
    self.subtitle = subtitle
    self.body = body
    self.threadID = threadID
    self.sound = sound
    self.interruption = interruption
    self.relevance = relevance
    self.userInfo = userInfo
    self.category = category
    self.attachment = attachment
  }

  func withoutAttachment() -> UserNotificationSpec {
    UserNotificationSpec(
      identifier: identifier, title: title, subtitle: subtitle, body: body, threadID: threadID,
      sound: sound, interruption: interruption, relevance: relevance, userInfo: userInfo,
      category: category, attachment: nil)
  }
}

/// A notification the center still shows.
public struct DeliveredNotification: Sendable, Hashable {
  public let identifier: String
  public let userInfo: [String: String]

  public init(identifier: String, userInfo: [String: String]) {
    self.identifier = identifier
    self.userInfo = userInfo
  }
}

/// `UNNotificationSettings` as plain values, so the mapping to `NotificationPermission` is
/// testable without a bundled process.
public struct NotificationSettingsSnapshot: Sendable, Hashable {
  public var authorization: UNAuthorizationStatus
  public var alertStyle: UNAlertStyle
  public var sound: UNNotificationSetting
  public var badge: UNNotificationSetting
  public var notificationCenter: UNNotificationSetting
  public var lockScreen: UNNotificationSetting
  public var timeSensitive: UNNotificationSetting
  public var scheduledDelivery: UNNotificationSetting

  public init(
    authorization: UNAuthorizationStatus, alertStyle: UNAlertStyle = .banner,
    sound: UNNotificationSetting = .enabled, badge: UNNotificationSetting = .enabled,
    notificationCenter: UNNotificationSetting = .enabled,
    lockScreen: UNNotificationSetting = .enabled, timeSensitive: UNNotificationSetting = .enabled,
    scheduledDelivery: UNNotificationSetting = .disabled
  ) {
    self.authorization = authorization
    self.alertStyle = alertStyle
    self.sound = sound
    self.badge = badge
    self.notificationCenter = notificationCenter
    self.lockScreen = lockScreen
    self.timeSensitive = timeSensitive
    self.scheduledDelivery = scheduledDelivery
  }
}

/// The part of `UNUserNotificationCenter` this app uses, in `Sendable` values.
///
/// `UNUserNotificationCenter.current()` aborts in a process without an app bundle, so only
/// `LiveNotificationCenter` may touch it and tests use a fake.
public protocol NotificationCenterClient: Sendable {
  /// Maps a center refusal to `.permissionDenied` and anything else to `.storage`.
  func add(_ spec: UserNotificationSpec) async throws(NtfyError)
  /// Unknown identifiers are ignored.
  func removeDelivered(identifiers: [String]) async
  func delivered() async -> [DeliveredNotification]
  /// Replaces the registered categories; the poster owns the set and always sends all of it.
  func setCategories(_ categories: [NotificationCategorySpec]) async
  func settings() async -> NotificationSettingsSnapshot
  /// Asks for `[.alert, .sound, .badge]`; `false` when the user declined or the request failed.
  func requestAuthorization() async -> Bool
}
