import Foundation
import NtfyCore
import UserNotifications

/// The notification center's delegate: turns clicks and button presses into
/// `NotificationResponse`s for an injected handler, and decides how notifications present while
/// the app runs.
///
/// The async delegate methods return after the handler did, which is what calls the system's
/// completion handler. Notifications without our `userInfo` are ignored, except that a click on
/// the missed-message summary calls `onSummary`.
public final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate, Sendable {
  private let handler: @Sendable (NotificationResponse) async -> Void
  private let onSummary: @Sendable () async -> Void

  public init(
    handler: @escaping @Sendable (NotificationResponse) async -> Void,
    onSummary: @escaping @Sendable () async -> Void = {}
  ) {
    self.handler = handler
    self.onSummary = onSummary
  }

  /// Pure part of `didReceive` for the summary, for tests: a body click on a notification whose
  /// request identifier is a summary's.
  public static func isSummaryClick(actionIdentifier: String, requestIdentifier: String) -> Bool {
    actionIdentifier == UNNotificationDefaultActionIdentifier
      && requestIdentifier.hasPrefix(UserNotificationMapper.summaryPrefix)
  }

  /// Pure part of `didReceive`, for tests.
  public static func response(
    actionIdentifier: String, userInfo: [AnyHashable: Any]
  ) -> NotificationResponse? {
    guard let ref = UserNotificationMapper.messageRef(from: userInfo) else { return nil }
    let kind: NotificationResponse.Kind
    switch actionIdentifier {
    case UNNotificationDefaultActionIdentifier: kind = .body
    case UNNotificationDismissActionIdentifier: kind = .dismissed
    default: kind = .button(id: actionIdentifier)
    }
    return NotificationResponse(ref: ref, kind: kind)
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter, willPresent notification: UNNotification
  ) async -> UNNotificationPresentationOptions {
    [.banner, .sound, .list]
  }

  public func userNotificationCenter(
    _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
  ) async {
    let mapped = Self.response(
      actionIdentifier: response.actionIdentifier,
      userInfo: response.notification.request.content.userInfo)
    if let mapped {
      await handler(mapped)
      return
    }
    if Self.isSummaryClick(
      actionIdentifier: response.actionIdentifier,
      requestIdentifier: response.notification.request.identifier)
    {
      await onSummary()
    }
  }
}
