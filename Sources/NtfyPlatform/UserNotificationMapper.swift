import Foundation
import NtfyCore
import UserNotifications

/// The pure translation between our values and UserNotifications objects.
public enum UserNotificationMapper {
  /// The only keys in `userInfo`: the response handler looks everything else up in the history.
  public static let topicKey = "topic"
  public static let idKey = "id"
  /// The identifier prefix of the missed-message summary, which has no `userInfo`.
  public static let summaryPrefix = "summary/"
  static let categoryPrefix = "ntfy:"
  static let attachmentIdentifier = "image"

  // MARK: Content to spec

  public static func spec(for content: NotificationContent, attachment: URL?)
    -> UserNotificationSpec
  {
    let category = content.buttons.isEmpty ? nil : category(for: content)
    return UserNotificationSpec(
      identifier: content.identifier, title: content.title, subtitle: content.subtitle,
      body: content.body, threadID: content.threadID, sound: content.sound,
      interruption: content.interruption, relevance: content.relevance,
      userInfo: userInfo(for: content.messageRef), category: category, attachment: attachment)
  }

  public static func summarySpec(
    count: Int, oldestTopic: String, cause: MissedSummaryCause = .away, identifier: String
  ) -> UserNotificationSpec {
    let body =
      switch cause {
      case .away: "\(count) notifications while you were away (\(oldestTopic))"
      case .meeting:
        "\(count) \(count == 1 ? "message" : "messages") while you were in a meeting"
      }
    return UserNotificationSpec(
      identifier: identifier, title: "ntfy-mac", subtitle: "Open ntfy to review",
      body: body, threadID: nil,
      sound: "Pop", interruption: .active, relevance: 0.5, userInfo: [:], category: nil,
      attachment: nil)
  }

  /// One category per notification, because the buttons differ per message.
  public static func category(for content: NotificationContent) -> NotificationCategorySpec {
    NotificationCategorySpec(
      identifier: categoryPrefix + content.identifier,
      actions: content.buttons.map { NotificationActionSpec(id: $0.id, title: $0.title) })
  }

  /// The notification identifier a category of ours belongs to.
  static func notificationIdentifier(ofCategory identifier: String) -> String? {
    identifier.hasPrefix(categoryPrefix) ? String(identifier.dropFirst(categoryPrefix.count)) : nil
  }

  static func userInfo(for ref: MessageRef) -> [String: String] {
    [topicKey: ref.topic, idKey: ref.id]
  }

  /// `nil` unless both keys are present as strings.
  public static func messageRef(from userInfo: [AnyHashable: Any]) -> MessageRef? {
    guard let topic = userInfo[topicKey] as? String, let id = userInfo[idKey] as? String,
      !topic.isEmpty, !id.isEmpty
    else { return nil }
    return MessageRef(topic: topic, id: id)
  }

  // MARK: Spec to UserNotifications

  public static func content(from spec: UserNotificationSpec) -> UNMutableNotificationContent {
    let content = UNMutableNotificationContent()
    content.title = spec.title
    content.subtitle = spec.subtitle
    content.body = spec.body
    if let thread = spec.threadID { content.threadIdentifier = thread }
    if let sound = spec.sound {
      content.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: sound))
    }
    content.interruptionLevel = level(spec.interruption)
    content.relevanceScore = spec.relevance
    content.userInfo = spec.userInfo
    if let category = spec.category { content.categoryIdentifier = category.identifier }
    if let file = spec.attachment,
      let attachment = try? UNNotificationAttachment(
        identifier: attachmentIdentifier, url: file, options: nil)
    {
      content.attachments = [attachment]
    }
    return content
  }

  public static func category(from spec: NotificationCategorySpec) -> UNNotificationCategory {
    let actions = spec.actions.map {
      UNNotificationAction(identifier: $0.id, title: $0.title, options: [])
    }
    return UNNotificationCategory(
      identifier: spec.identifier, actions: actions, intentIdentifiers: [], options: [])
  }

  public static func spec(from category: UNNotificationCategory) -> NotificationCategorySpec {
    NotificationCategorySpec(
      identifier: category.identifier,
      actions: category.actions.map { NotificationActionSpec(id: $0.identifier, title: $0.title) })
  }

  static func level(_ level: InterruptionLevel) -> UNNotificationInterruptionLevel {
    switch level {
    case .passive: .passive
    case .active: .active
    case .timeSensitive: .timeSensitive
    }
  }

  // MARK: Errors

  /// A refusal by the system is a permission problem; everything else is reported as `.storage`.
  public static func error(from error: any Error) -> NtfyError {
    if let error = error as? NtfyError { return error }
    if (error as? UNError)?.code == .notificationsNotAllowed { return .permissionDenied }
    return .storage("notification center: \(error.localizedDescription)")
  }
}
