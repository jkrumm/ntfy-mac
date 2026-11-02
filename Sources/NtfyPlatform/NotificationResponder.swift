import Foundation
import NtfyCore
import UserNotifications

/// The notification center's delegate: turns clicks and button presses into
/// `NotificationResponse`s for an injected handler, and decides how notifications present while
/// the app runs.
///
/// The async delegate methods return after the handler did, which is what calls the system's
/// completion handler. Notifications without our `userInfo` (the missed-message summary) are
/// ignored.
public final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate, Sendable {
  private let handler: @Sendable (NotificationResponse) async -> Void

  public init(handler: @escaping @Sendable (NotificationResponse) async -> Void) {
    self.handler = handler
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
    guard let mapped else { return }
    await handler(mapped)
  }
}
