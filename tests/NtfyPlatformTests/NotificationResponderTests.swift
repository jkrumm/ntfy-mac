import NtfyCore
import Testing
import UserNotifications

@testable import NtfyPlatform

@Suite struct NotificationResponderTests {
  private let info: [AnyHashable: Any] = ["topic": "alerts", "id": "abc"]
  private let ref = MessageRef(topic: "alerts", id: "abc")

  @Test func defaultActionIsTheBody() {
    let response = NotificationResponder.response(
      actionIdentifier: UNNotificationDefaultActionIdentifier, userInfo: info)
    #expect(response == NotificationResponse(ref: ref, kind: .body))
  }

  @Test func dismissActionIsDismissed() {
    let response = NotificationResponder.response(
      actionIdentifier: UNNotificationDismissActionIdentifier, userInfo: info)
    #expect(response == NotificationResponse(ref: ref, kind: .dismissed))
  }

  @Test func anythingElseIsAButton() {
    let response = NotificationResponder.response(actionIdentifier: "acknowledge", userInfo: info)
    #expect(response == NotificationResponse(ref: ref, kind: .button(id: "acknowledge")))
  }

  @Test func malformedUserInfoIsIgnored() {
    for bad: [AnyHashable: Any] in [[:], ["topic": "alerts"], ["topic": 1, "id": 2]] {
      #expect(NotificationResponder.response(actionIdentifier: "x", userInfo: bad) == nil)
    }
  }
}
