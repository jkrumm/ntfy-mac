import Foundation
import NtfyCore
import NtfyTesting
import Testing

@testable import NtfyPlatform

@Suite struct UserNotificationPosterTests {
  private func poster(
    _ center: FakeNotificationCenter, images: StubImageFetcher = StubImageFetcher(),
    entitlements: FixedEntitlements = FixedEntitlements([.timeSensitiveNotifications])
  ) -> UserNotificationPoster {
    UserNotificationPoster(center: center, images: images, entitlements: entitlements)
  }

  /// Polls in real time: yielding a fixed number of times proves nothing on a busy pool.
  private func eventually(_ condition: () async -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while !(await condition()), ContinuousClock.now < deadline {
      try? await Task.sleep(for: .milliseconds(2))
    }
    return await condition()
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

  @Test func timeSensitiveIsKeptOnlyWithTheEntitlement() async throws {
    let urgent = NotificationFixtures.content(NotificationFixtures.message(priority: .max))
    let granted = FakeNotificationCenter()
    try await poster(granted).post(urgent)
    #expect(await granted.added.first?.interruption == .timeSensitive)

    let missing = FakeNotificationCenter()
    try await poster(missing, entitlements: FixedEntitlements()).post(urgent)
    #expect(await missing.added.first?.interruption == .active)

    let plain = FakeNotificationCenter()
    try await poster(plain, entitlements: FixedEntitlements()).post(
      NotificationFixtures.content(NotificationFixtures.message(priority: .low)))
    #expect(await plain.added.first?.interruption == .active)
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
    let poster = poster(center)
    for index in 0..<(UserNotificationPoster.maxCategories + 6) {
      try await poster.post(withButtons(id: "n\(index)"))
    }
    let registered = await center.registered
    #expect(registered.count == UserNotificationPoster.maxCategories)
    #expect(
      registered.first?.identifier == "ntfy:alerts/n\(UserNotificationPoster.maxCategories + 5)")
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

  @Test func interleavedPostsAndARestoreKeepEveryCategory() async throws {
    let center = FakeNotificationCenter()
    let poster = poster(center)
    let first = withButtons(id: "first")
    let second = withButtons(id: "second")
    let restored = withButtons(id: "restored")
    await center.holdNextAdd()

    let postA = Task { try await poster.post(first) }
    #expect(await eventually { await center.isHoldingAdd })

    // Tasks do not start in creation order on a busy pool, and the gate serves in arrival
    // order: the restore only survives the second post's pruning by running after it.
    let postB = Task { try await poster.post(second) }
    #expect(await eventually { await poster.gateQueueLength == 1 })
    let restore = Task { await poster.restoreCategories(for: [restored]) }
    #expect(await eventually { await poster.gateQueueLength == 2 })
    // Both wait behind the first post: nothing else touched the center meanwhile.
    #expect(
      await center.calls == [.remove(["alerts/first"]), .setCategories, .add("alerts/first")])

    await center.releaseHeldAdd()
    try await postA.value
    try await postB.value
    await restore.value

    let registered = Set(await center.registered.map(\.identifier))
    #expect(registered == ["ntfy:alerts/first", "ntfy:alerts/second", "ntfy:alerts/restored"])
    let added = await center.added
    #expect(added.map(\.identifier) == ["alerts/first", "alerts/second"])
    for spec in added { #expect(registered.contains(try #require(spec.category?.identifier))) }
  }

  @Test func aFailedPostReleasesTheGate() async throws {
    let center = FakeNotificationCenter()
    await center.failNextAdds(1, with: .storage("boom"))
    let poster = poster(center)
    await #expect(throws: NtfyError.storage("boom")) {
      try await poster.post(NotificationFixtures.content())
    }
    try await poster.post(withButtons(id: "next"))
    #expect(await center.registered.map(\.identifier) == ["ntfy:alerts/next"])
  }
}
