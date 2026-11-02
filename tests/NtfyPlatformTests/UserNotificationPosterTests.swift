import Foundation
import NtfyCore
import NtfyTesting
import Testing

@testable import NtfyPlatform

@Suite struct UserNotificationPosterTests {
  private func poster(
    _ center: FakeNotificationCenter, images: StubImageFetcher = StubImageFetcher()
  ) -> UserNotificationPoster {
    UserNotificationPoster(center: center, images: images)
  }

  private func withButtons(id: String = "abc12345") -> NotificationContent {
    NotificationFixtures.content(
      NotificationFixtures.message(
        id: id, actions: [NotificationFixtures.viewAction("Open")]))
  }

  @Test func postReplacesByRemovingThenRegisteringThenAdding() async throws {
    let center = FakeNotificationCenter()
    try await poster(center).post(withButtons())
    let calls = await center.calls
    #expect(calls == [.remove(["alerts/abc12345"]), .setCategories, .add("alerts/abc12345")])
    let registered = await center.registered
    #expect(registered.map(\.identifier) == ["ntfy:alerts/abc12345"])
  }

  @Test func postingAgainReplacesTheDeliveredOne() async throws {
    let center = FakeNotificationCenter()
    let poster = poster(center)
    try await poster.post(withButtons())
    try await poster.post(withButtons())
    #expect(await poster.deliveredIdentifiers() == ["alerts/abc12345"])
    #expect(await center.added.count == 2)
  }

  @Test func contentWithoutButtonsRegistersNothing() async throws {
    let center = FakeNotificationCenter()
    try await poster(center).post(NotificationFixtures.content())
    #expect(await center.calls == [.remove(["alerts/abc12345"]), .add("alerts/abc12345")])
  }

  @Test func categoriesOfOtherDeliveredNotificationsAreMerged() async throws {
    let center = FakeNotificationCenter()
    let poster = poster(center)
    try await poster.post(withButtons(id: "one"))
    try await poster.post(withButtons(id: "two"))
    let ids = await center.registered.map(\.identifier).sorted()
    #expect(ids == ["ntfy:alerts/one", "ntfy:alerts/two"])
  }

  @Test func categoriesOfGoneNotificationsAreDropped() async throws {
    let center = FakeNotificationCenter()
    let poster = poster(center)
    try await poster.post(withButtons(id: "one"))
    await poster.remove(identifiers: ["alerts/one"])
    try await poster.post(withButtons(id: "two"))
    #expect(await center.registered.map(\.identifier) == ["ntfy:alerts/two"])
  }

  @Test func categorySetIsBounded() async throws {
    let center = FakeNotificationCenter()
    let many = (0..<100).map { index in
      NotificationCategorySpec(identifier: "ntfy:alerts/\(index)", actions: [])
    }
    await center.setRegistered(many)
    await center.setShown(
      (0..<100).map { DeliveredNotification(identifier: "alerts/\($0)", userInfo: [:]) })
    try await poster(center).post(withButtons(id: "fresh"))
    let registered = await center.registered
    #expect(registered.count == UserNotificationPoster.maxCategories)
    #expect(registered.first?.identifier == "ntfy:alerts/fresh")
  }

  @Test func deniedCenterThrowsPermissionDenied() async {
    let center = FakeNotificationCenter()
    await center.failAdds(with: .permissionDenied)
    await #expect(throws: NtfyError.permissionDenied) {
      try await poster(center).post(NotificationFixtures.content())
    }
  }

  @Test func otherFailuresPropagateAsStorage() async {
    let center = FakeNotificationCenter()
    await center.failAdds(with: .storage("boom"))
    await #expect(throws: NtfyError.storage("boom")) {
      try await poster(center).post(NotificationFixtures.content())
    }
  }

  @Test func imageIsFetchedAndAttached() async throws {
    let center = FakeNotificationCenter()
    let file = try NotificationFixtures.pngFile()
    let message = NotificationFixtures.message(image: URL(string: "https://example.com/i.png"))
    try await poster(center, images: StubImageFetcher(file: file)).post(
      NotificationFixtures.content(message))
    #expect(await center.added.first?.attachment == file)
  }

  @Test func rejectedAttachmentIsRetriedWithoutIt() async throws {
    let center = FakeNotificationCenter()
    await center.failNextAdds(1, with: .storage("bad attachment"))
    let file = try NotificationFixtures.pngFile()
    let message = NotificationFixtures.message(image: URL(string: "https://example.com/i.png"))
    try await poster(center, images: StubImageFetcher(file: file)).post(
      NotificationFixtures.content(message))
    let added = await center.added
    #expect(added.count == 1)
    #expect(added.first?.attachment == nil)
  }

  @Test func deniedWithAttachmentIsNotRetried() async throws {
    let center = FakeNotificationCenter()
    await center.failAdds(with: .permissionDenied)
    let file = try NotificationFixtures.pngFile()
    let message = NotificationFixtures.message(image: URL(string: "https://example.com/i.png"))
    await #expect(throws: NtfyError.permissionDenied) {
      try await poster(center, images: StubImageFetcher(file: file)).post(
        NotificationFixtures.content(message))
    }
    #expect(await center.calls.filter { $0 == .add("alerts/abc12345") }.count == 1)
  }

  @Test func failedFetchPostsWithoutAttachment() async throws {
    let center = FakeNotificationCenter()
    let message = NotificationFixtures.message(image: URL(string: "https://example.com/i.png"))
    try await poster(center).post(NotificationFixtures.content(message))
    let added = await center.added
    #expect(added.count == 1)
    #expect(added.first?.attachment == nil)
  }

  @Test func summaryIsAddedOnceWithoutUserInfo() async throws {
    let center = FakeNotificationCenter()
    try await poster(center).postMissedSummary(count: 4, oldestTopic: "alerts")
    let added = await center.added
    #expect(added.count == 1)
    #expect(added.first?.body == "4 notifications while you were away (alerts)")
    #expect(added.first?.userInfo.isEmpty == true)
  }

  @Test func removeAndDeliveredPassThrough() async throws {
    let center = FakeNotificationCenter()
    let poster = poster(center)
    try await poster.post(NotificationFixtures.content())
    await poster.remove(identifiers: [])
    #expect(await poster.deliveredIdentifiers() == ["alerts/abc12345"])
    await poster.remove(identifiers: ["alerts/abc12345", "unknown"])
    #expect(await poster.deliveredIdentifiers().isEmpty)
  }

  @Test func restoreRegistersCategoriesOfDeliveredNotifications() async throws {
    let center = FakeNotificationCenter()
    await center.setShown([
      DeliveredNotification(
        identifier: "alerts/one", userInfo: ["topic": "alerts", "id": "one"]),
      DeliveredNotification(identifier: "summary/x", userInfo: [:]),
    ])
    let poster = poster(center)
    await poster.restoreCategories(for: [withButtons(id: "one"), NotificationFixtures.content()])
    #expect(await center.registered.map(\.identifier) == ["ntfy:alerts/one"])
    #expect(await poster.deliveredRefs() == [MessageRef(topic: "alerts", id: "one")])
  }

  @Test func restoreWithoutButtonsTouchesNothing() async {
    let center = FakeNotificationCenter()
    await poster(center).restoreCategories(for: [NotificationFixtures.content()])
    #expect(await center.calls.isEmpty)
  }

  @Test func restoreThroughHistoryRebuildsOnlyKnownNotifications() async throws {
    let center = FakeNotificationCenter()
    let history = InMemoryHistoryStore()
    let known = NotificationFixtures.message(
      id: "one", actions: [NotificationFixtures.viewAction("Open")])
    try await history.append(known)
    await center.setShown([
      DeliveredNotification(identifier: "alerts/one", userInfo: ["topic": "alerts", "id": "one"]),
      DeliveredNotification(
        identifier: "alerts/gone", userInfo: ["topic": "alerts", "id": "gone"]),
      DeliveredNotification(identifier: "summary/x", userInfo: [:]),
    ])
    await poster(center).restoreDeliveredCategories(inbox: history, config: Config())
    #expect(await center.registered.map(\.identifier) == ["ntfy:alerts/one"])
  }
}
