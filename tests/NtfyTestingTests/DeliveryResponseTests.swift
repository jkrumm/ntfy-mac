import Foundation
import NtfyCore
import NtfyTesting
import Testing

@Suite struct DeliveryUserResponseTests {
  @Test func acknowledgingRecordsItAndWithdrawsTheNotification() async throws {
    let rig = DeliveryRig()
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    await rig.service.acknowledge(topic: "t", id: "a")
    let stored = await rig.history.entries(HistoryQuery()).first
    #expect(stored?.isAcknowledged == true)
    #expect(await rig.poster.removed == ["t/a"])
    await rig.service.shutdown()
  }

  @Test func openingMarksTheMessageReadAndAcknowledged() async throws {
    let rig = DeliveryRig()
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    await rig.service.opened(topic: "t", id: "a")
    let stored = await rig.history.entries(HistoryQuery()).first
    #expect(stored?.isRead == true)
    #expect(stored?.isAcknowledged == true)
    #expect(await rig.poster.removed == ["t/a"])
    await rig.service.shutdown()
  }

  @Test func theNotificationOfAnUpdatedSequenceIsFoundThroughTheHistory() async throws {
    let rig = DeliveryRig()
    try await rig.receive("a", priority: 4, sequence: "seq")
    #expect(await rig.waitForPosts(1))
    #expect(rig.clock.sleeperCount == 0)
    await rig.service.acknowledge(topic: "t", id: "a")
    #expect(await rig.poster.removed == ["t/seq"])
    await rig.service.shutdown()
  }

  @Test func acknowledgingAQueuedMessageDropsIt() async throws {
    let rig = DeliveryRig()
    try await rig.occupyTheSlot()
    try await rig.receive("queued")
    await rig.service.acknowledge(topic: "t", id: "queued")
    await rig.nextSlot()
    await rig.settle()
    #expect(await rig.poster.postedIDs == ["blocker"])
    await rig.service.shutdown()
  }
}

@Suite struct DeliveryServerResponseTests {
  @Test func aWithdrawalWhileQueuedDropsTheMessage() async throws {
    let rig = DeliveryRig()
    try await rig.occupyTheSlot()
    try await rig.receive("queued", sequence: "s")
    await rig.service.withdraw(topic: "t", sequenceID: "s")
    await rig.nextSlot()
    await rig.settle()
    #expect(await rig.poster.postedIDs == ["blocker"])
    #expect(await rig.history.recent(limit: 10).map(\.id) == ["blocker"])
    await rig.service.shutdown()
  }

  @Test func aWithdrawalWhileDeliveredRemovesTheNotificationAndHidesTheHistory() async throws {
    let rig = DeliveryRig()
    try await rig.receive("a", sequence: "s")
    #expect(await rig.waitForPosts(1))
    await rig.service.withdraw(topic: "t", sequenceID: "s")
    #expect(await rig.poster.removed == ["t/s"])
    #expect(await rig.poster.deliveredIdentifiers().isEmpty)
    #expect(await rig.history.recent(limit: 10).isEmpty)
    await rig.service.shutdown()
  }

  @Test func aClearWhileQueuedDropsTheMessageAndSettlesIt() async throws {
    let rig = DeliveryRig()
    try await rig.occupyTheSlot()
    try await rig.receive("queued", sequence: "s")
    await rig.service.clear(topic: "t", sequenceID: "s")
    await rig.nextSlot()
    await rig.settle()
    #expect(await rig.poster.postedIDs == ["blocker"])
    let stored = await rig.history.entries(HistoryQuery(topic: "t")).first
    #expect(stored?.isAcknowledged == true)
    await rig.service.shutdown()
  }

  @Test func aClearWhileDeliveredRemovesTheNotificationAndMarksItRead() async throws {
    let rig = DeliveryRig()
    try await rig.receive("a", sequence: "s")
    #expect(await rig.waitForPosts(1))
    await rig.service.clear(topic: "t", sequenceID: "s")
    #expect(await rig.poster.removed == ["t/s"])
    let stored = await rig.history.entries(HistoryQuery()).first
    #expect(stored?.isRead == true)
    #expect(stored?.isAcknowledged == true)
    await rig.service.shutdown()
  }
}

@Suite struct DeliveryUpdateTests {
  @Test func anUpdateReplacesTheQueuedNotification() async throws {
    let rig = DeliveryRig()
    try await rig.occupyTheSlot()
    try await rig.receive("v1", sequence: "s")
    try await rig.receive("v2", sequence: "s")
    await rig.nextSlot()
    #expect(await rig.waitForPosts(2))
    await rig.nextSlot()
    await rig.settle()
    #expect(await rig.poster.postedIDs == ["blocker", "v2"])
    await rig.service.shutdown()
  }

  @Test func anUpdateOfADeliveredNotificationPostsUnderTheSameIdentifier() async throws {
    let rig = DeliveryRig()
    try await rig.receive("v1", sequence: "s")
    #expect(await rig.waitForPosts(1))
    try await rig.receive("v2", sequence: "s")
    await rig.nextSlot()
    #expect(await rig.waitForPosts(2))
    #expect(await rig.poster.postedIdentifiers == ["t/s", "t/s"])
    #expect(await rig.poster.postedIDs == ["v1", "v2"])
    await rig.service.shutdown()
  }

  @Test func anUpdateRestartsTheDismissTimerOfTheNotification() async throws {
    let rig = DeliveryRig(config: Config(reAlert: false))
    try await rig.receive("v1", sequence: "s")
    #expect(await rig.waitForPosts(1))
    try await rig.receive("v2", sequence: "s")
    await rig.nextSlot()
    #expect(await rig.waitForPosts(2))
    #expect(await rig.waitForSleepers(1))
    // 8 s after v1, but only 6.5 s after v2.
    await rig.advance(6.5)
    #expect(await rig.poster.removed.isEmpty)
    await rig.advance(1.5)
    #expect(await rig.eventually { await rig.poster.removed == ["t/s"] })
    await rig.service.shutdown()
  }

  @Test func aDuplicateOfAPendingMessageIsIgnored() async throws {
    let rig = DeliveryRig()
    try await rig.occupyTheSlot()
    let message = try await rig.receive("queued")
    await rig.service.deliver(message)
    await rig.nextSlot()
    #expect(await rig.waitForPosts(2))
    await rig.nextSlot()
    await rig.settle()
    #expect(await rig.poster.postedIDs == ["blocker", "queued"])
    await rig.service.shutdown()
  }
}

/// A poster whose `post` waits until the test lets it finish, to act while a post is running.
private actor GatedPoster: NotificationPoster {
  private var gates: [CheckedContinuation<Void, Never>] = []
  private(set) var arrivals = 0
  private(set) var removed: [String] = []

  func post(_ content: NotificationContent) async throws(NtfyError) {
    arrivals += 1
    await withCheckedContinuation { gates.append($0) }
  }

  func postMissedSummary(count: Int, oldestTopic: String) {}
  func remove(identifiers: [String]) { removed.append(contentsOf: identifiers) }
  func deliveredIdentifiers() -> Set<String> { [] }

  func release() {
    let waiting = gates
    gates = []
    for gate in waiting { gate.resume() }
  }
}

@Suite struct DeliveryInFlightTests {
  private func service(_ poster: GatedPoster, clock: FakeClock) -> (
    DeliveryService, InMemoryHistoryStore
  ) {
    let history = InMemoryHistoryStore(clock: clock)
    let service = DeliveryService(
      poster: poster, history: history, inbox: history,
      config: InMemoryConfigStore(Config(reAlertIntervalSeconds: 60)), clock: clock)
    return (service, history)
  }

  private func waitForArrivals(_ count: Int, _ poster: GatedPoster) async -> Bool {
    for _ in 0..<200_000 {
      if await poster.arrivals >= count { return true }
      await Task.yield()
    }
    return false
  }

  @Test func aWithdrawalDuringThePostRemovesTheNotificationOnceItIsShown() async throws {
    let clock = FakeClock()
    let poster = GatedPoster()
    let (service, history) = service(poster, clock: clock)
    let message = NtfyMessage(
      id: "u", topic: "t", time: clock.now(), body: "b", priority: .max, sequenceID: "s")
    try await history.append(message)
    await service.deliver(message)
    #expect(await waitForArrivals(1, poster))

    await service.withdraw(topic: "t", sequenceID: "s")
    await poster.release()
    for _ in 0..<200_000 where await poster.removed.count < 2 { await Task.yield() }
    #expect(await poster.removed == ["t/s", "t/s"])
    #expect(clock.sleeperCount == 0)
    await service.shutdown()
  }

  @Test func anUpdateDuringThePostLeavesTheOlderOneWithoutTimers() async throws {
    let clock = FakeClock()
    let poster = GatedPoster()
    let (service, history) = service(poster, clock: clock)
    let first = NtfyMessage(
      id: "v1", topic: "t", time: clock.now(), body: "b", priority: .max, sequenceID: "s")
    try await history.append(first)
    await service.deliver(first)
    #expect(await waitForArrivals(1, poster))

    let second = NtfyMessage(
      id: "v2", topic: "t", time: clock.now(), body: "b", priority: .max, sequenceID: "s")
    try await history.append(second)
    await service.deliver(second)
    await poster.release()
    for _ in 0..<3000 { await Task.yield() }
    #expect(await poster.removed.isEmpty)
    // Only the drain, waiting for the slot of the update; no re-alert for the older message.
    #expect(clock.sleeperCount == 1)
    await service.shutdown()
  }
}
