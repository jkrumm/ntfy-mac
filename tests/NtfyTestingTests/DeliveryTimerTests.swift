import Foundation
import NtfyCore
import NtfyTesting
import Testing

@Suite struct DeliveryDismissTests {
  @Test func aNotificationIsRemovedAfterTheDismissDurationOfItsPriority() async throws {
    let rig = DeliveryRig(config: Config())
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    #expect(await rig.waitForSleepers(1))
    await rig.advance(7.9)
    #expect(await rig.poster.removed.isEmpty)
    await rig.advance(0.1)
    #expect(await rig.eventually { await rig.poster.removed == ["t/a"] })
    await rig.service.shutdown()
  }

  @Test func theConfigOverridesTheDismissDuration() async throws {
    let rig = DeliveryRig(config: Config(dismiss: [3: 2]))
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    #expect(await rig.waitForSleepers(1))
    await rig.advance(2)
    #expect(await rig.eventually { await rig.poster.removed == ["t/a"] })
    await rig.service.shutdown()
  }

  @Test func acknowledgingCancelsTheDismissal() async throws {
    let rig = DeliveryRig(config: Config())
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    #expect(await rig.waitForSleepers(1))
    await rig.service.acknowledge(topic: "t", id: "a")
    #expect(await rig.poster.removed == ["t/a"])
    #expect(rig.clock.sleeperCount == 0)
    await rig.advance(30)
    #expect(await rig.poster.removed == ["t/a"])
    await rig.service.shutdown()
  }

  @Test func aNotificationWithoutADismissDurationStays() async throws {
    let rig = DeliveryRig(config: Config(reAlert: false))
    try await rig.receive("a", priority: 4)
    #expect(await rig.waitForPosts(1))
    await rig.settle()
    #expect(rig.clock.sleeperCount == 0)
    await rig.service.shutdown()
  }
}

@Suite struct DeliveryRealertTests {
  private static let config = Config(
    dismiss: [1: 0, 2: 0, 3: 0, 4: 0, 5: 0], reAlertIntervalSeconds: 60, reAlertMaxRepeats: 3)

  /// Posts an urgent message and waits until its re-alert timer runs.
  private func urgent(_ rig: DeliveryRig) async throws {
    try await rig.receive("u", priority: 5, sequence: "s")
    #expect(await rig.waitForPosts(1))
    #expect(await rig.waitForSleepers(1))
  }

  @Test func anUnacknowledgedMessageIsPostedAgainEveryIntervalUpToTheMaximum() async throws {
    let rig = DeliveryRig(config: Self.config)
    try await urgent(rig)
    for posts in 2...4 {
      await rig.advance(59)
      #expect(await rig.poster.posted.count == posts - 1)
      await rig.advance(1)
      #expect(await rig.waitForPosts(posts))
      if posts < 4 { #expect(await rig.waitForSleepers(1)) }
    }
    await rig.settle()
    #expect(rig.clock.sleeperCount == 0)
    await rig.advance(600)
    #expect(await rig.poster.posted.count == 4)
    #expect(await rig.poster.postedIdentifiers == Array(repeating: "t/s", count: 4))
    await rig.service.shutdown()
  }

  @Test func aPostedUrgentMessageIsMarkedNotified() async throws {
    let rig = DeliveryRig(config: Self.config)
    try await urgent(rig)
    #expect(await rig.history.unnotified(limit: 10, offset: 0).isEmpty)
    await rig.service.shutdown()
  }

  @Test func acknowledgingStopsTheReAlerts() async throws {
    let rig = DeliveryRig(config: Self.config)
    try await urgent(rig)
    await rig.service.acknowledge(topic: "t", id: "u")
    await rig.advance(600)
    #expect(await rig.poster.posted.count == 1)
    #expect(await rig.history.unacknowledged(minPriority: .max).isEmpty)
    await rig.service.shutdown()
  }

  @Test func openingTheNotificationStopsTheReAlerts() async throws {
    let rig = DeliveryRig(config: Self.config)
    try await urgent(rig)
    await rig.service.opened(topic: "t", id: "u")
    await rig.advance(600)
    #expect(await rig.poster.posted.count == 1)
    await rig.service.shutdown()
  }

  @Test func aWithdrawalStopsTheReAlerts() async throws {
    let rig = DeliveryRig(config: Self.config)
    try await urgent(rig)
    await rig.service.withdraw(topic: "t", sequenceID: "s")
    await rig.advance(600)
    #expect(await rig.poster.posted.count == 1)
    await rig.service.shutdown()
  }

  @Test func clearingStopsTheReAlerts() async throws {
    let rig = DeliveryRig(config: Self.config)
    try await urgent(rig)
    await rig.service.clear(topic: "t", sequenceID: "s")
    await rig.advance(600)
    #expect(await rig.poster.posted.count == 1)
    await rig.service.shutdown()
  }

  @Test func switchingReAlertOffStopsThePendingOnesAtTheNextTick() async throws {
    let rig = DeliveryRig(config: Self.config)
    try await urgent(rig)
    await rig.config.update { $0.reAlert = false }
    await rig.advance(60)
    await rig.settle()
    #expect(await rig.poster.posted.count == 1)
    #expect(rig.clock.sleeperCount == 0)
    await rig.service.shutdown()
  }

  @Test func aReAlertThatExhaustsItsRetriesKeepsTheChainAlive() async throws {
    let rig = DeliveryRig(config: Self.config)
    try await urgent(rig)
    await rig.poster.failNext(3)
    await rig.advance(60)
    for attempts in 2...4 {
      #expect(await rig.waitForAttempts(attempts))
      if attempts < 4 { await rig.nextSlot() }
    }
    await rig.settle()
    #expect(await rig.poster.posted.count == 1)
    // The next tick is armed and the repeat budget is still there.
    #expect(await rig.waitForSleepers(1))
    await rig.advance(60)
    #expect(await rig.waitForPosts(2))
    await rig.service.shutdown()
  }

  @Test func aMessageBelowTheThresholdIsNotReAlerted() async throws {
    let rig = DeliveryRig(config: Self.config)
    try await rig.receive("n", priority: 4)
    #expect(await rig.waitForPosts(1))
    await rig.settle()
    #expect(rig.clock.sleeperCount == 0)
    await rig.service.shutdown()
  }
}
