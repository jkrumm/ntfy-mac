import Foundation
import NtfyCore
import Testing
import UserNotifications

@testable import NtfyPlatform

@Suite struct UserNotificationMapperTests {
  private func mapped(
    _ content: NotificationContent, attachment: URL? = nil
  ) -> (spec: UserNotificationSpec, content: UNMutableNotificationContent) {
    let spec = UserNotificationMapper.spec(for: content, attachment: attachment)
    return (spec, UserNotificationMapper.content(from: spec))
  }

  @Test(arguments: [
    (Priority.min, "Tink", UNNotificationInterruptionLevel.active, 0.0),
    (Priority.low, "Tink", UNNotificationInterruptionLevel.active, 0.25),
    (Priority.default, "Pop", UNNotificationInterruptionLevel.active, 0.5),
    (Priority.high, "Ping", UNNotificationInterruptionLevel.timeSensitive, 0.75),
    (Priority.max, "Ping", UNNotificationInterruptionLevel.timeSensitive, 1.0),
  ])
  func everyPriorityProfileReachesTheContent(
    priority: Priority, sound: String, level: UNNotificationInterruptionLevel, relevance: Double
  ) {
    let source = NotificationFixtures.content(NotificationFixtures.message(priority: priority))
    let (spec, content) = mapped(source)
    #expect(spec.sound == sound)
    #expect(content.sound != nil)
    #expect(content.interruptionLevel == level)
    #expect(content.relevanceScore == relevance)
  }

  @Test func textAndThreadAreCopied() {
    let source = NotificationFixtures.content()
    let (_, content) = mapped(source)
    #expect(content.title == "Disk")
    #expect(content.subtitle == "alerts")
    #expect(content.body == "body")
    #expect(content.threadIdentifier == "alerts")
  }

  @Test func silentConfigMeansNoSound() {
    let config = Config(sounds: [3: .silent])
    let (spec, content) = mapped(NotificationFixtures.content(config: config))
    #expect(spec.sound == nil)
    #expect(content.sound == nil)
  }

  @Test func passiveAndTimeSensitiveLevelsMap() {
    #expect(UserNotificationMapper.level(.passive) == .passive)
    #expect(UserNotificationMapper.level(.active) == .active)
    #expect(UserNotificationMapper.level(.timeSensitive) == .timeSensitive)
  }

  @Test func userInfoHoldsOnlyTopicAndID() {
    let message = NotificationFixtures.message(
      image: URL(string: "https://example.com/i.png"),
      actions: [NotificationFixtures.viewAction("Open")])
    let (_, content) = mapped(NotificationFixtures.content(message))
    let keys = (content.userInfo as? [String: String]).map { Set($0.keys) }
    #expect(keys == ["topic", "id"])
    #expect(content.userInfo["topic"] as? String == "alerts")
    #expect(content.userInfo["id"] as? String == "abc12345")
  }

  @Test func buttonsBecomeActionsOfOneCategory() throws {
    let message = NotificationFixtures.message(
      actions: [NotificationFixtures.viewAction("One"), NotificationFixtures.viewAction("Two")])
    let (spec, content) = mapped(NotificationFixtures.content(message))
    let category = UserNotificationMapper.category(from: try #require(spec.category))
    #expect(content.categoryIdentifier == spec.category?.identifier)
    #expect(category.identifier == "ntfy:alerts/abc12345")
    #expect(category.actions.map(\.title) == ["One", "Two"])
    #expect(category.actions.allSatisfy { $0.options.isEmpty })
    #expect(category.actions.map(\.identifier) == spec.category?.actions.map(\.id))
  }

  @Test func noButtonsMeansNoCategory() {
    let (spec, content) = mapped(NotificationFixtures.content())
    #expect(spec.category == nil)
    #expect(content.categoryIdentifier.isEmpty)
  }

  @Test func categoryRoundTripsThroughUserNotifications() {
    let spec = NotificationCategorySpec(
      identifier: "ntfy:x", actions: [NotificationActionSpec(id: "a", title: "A")])
    #expect(
      UserNotificationMapper.spec(from: UserNotificationMapper.category(from: spec)) == spec)
  }

  @Test func validImageIsAttached() throws {
    let file = try NotificationFixtures.pngFile()
    let (_, content) = mapped(NotificationFixtures.content(), attachment: file)
    #expect(content.attachments.count == 1)
  }

  @Test func missingImageMeansNoAttachment() {
    let (_, content) = mapped(NotificationFixtures.content(), attachment: nil)
    #expect(content.attachments.isEmpty)
  }

  @Test func summaryCopiesTheOldTextAndStaysQuiet() {
    let spec = UserNotificationMapper.summarySpec(count: 7, oldestTopic: "alerts", identifier: "s")
    #expect(spec.body == "7 notifications while you were away (alerts)")
    #expect(spec.subtitle == "Open ntfy to review")
    #expect(spec.sound == "Pop")
    #expect(spec.userInfo.isEmpty)
  }

  @Test func meetingSummaryNamesTheMeetingAndCountsCorrectly() {
    let many = UserNotificationMapper.summarySpec(
      count: 3, oldestTopic: "alerts", cause: .meeting, identifier: "s")
    #expect(many.body == "3 messages while you were in a meeting")
    let one = UserNotificationMapper.summarySpec(
      count: 1, oldestTopic: "alerts", cause: .meeting, identifier: "s")
    #expect(one.body == "1 message while you were in a meeting")
    #expect(one.sound == "Pop")
    #expect(one.userInfo.isEmpty)
  }

  @Test func errorsMapToNtfyErrors() {
    #expect(
      UserNotificationMapper.error(from: UNError(.notificationsNotAllowed)) == .permissionDenied)
    #expect(UserNotificationMapper.error(from: NtfyError.unauthorized) == .unauthorized)
    guard case .storage = UserNotificationMapper.error(from: UNError(.attachmentInvalidURL)) else {
      Issue.record("expected .storage")
      return
    }
  }

  @Test func messageRefNeedsBothStringKeys() {
    #expect(
      UserNotificationMapper.messageRef(from: ["topic": "t", "id": "i"])
        == MessageRef(topic: "t", id: "i"))
    #expect(UserNotificationMapper.messageRef(from: ["topic": "t"]) == nil)
    #expect(UserNotificationMapper.messageRef(from: ["topic": "t", "id": 5]) == nil)
    #expect(UserNotificationMapper.messageRef(from: ["topic": "", "id": "i"]) == nil)
  }
}
