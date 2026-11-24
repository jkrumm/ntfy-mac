import Foundation
import NtfyCore
import NtfyTesting
import Testing

/// While the displays are dark nobody sees a banner, so a re-alert must not spend its repeats
/// there, and what needs an acknowledgement is posted again when someone is back.
@Suite struct DeliveryPresenceTests {
  private static let config = Config(
    dismiss: [1: 0, 2: 0, 3: 0, 4: 0, 5: 0], reAlertIntervalSeconds: 60, reAlertMaxRepeats: 3)

  /// The reminder poll and the re-alert timer.
  private static let sleepers = 2

  private let events = ManualSystemEvents()

  private func rig(_ config: Config = Self.config) async -> DeliveryRig {
    let rig = DeliveryRig(config: config, presence: events)
    await rig.service.start()
    await rig.settle()
    return rig
  }

  private func send(_ event: SystemEvent, _ rig: DeliveryRig) async {
    events.send(event)
    await rig.settle()
  }

  @Test func aReAlertDueWhileAwayIsHeldAndPostedOnReturnWithAFullBudget() async throws {
    let rig = await rig()
    try await rig.receive("u", priority: 5, sequence: "s")
    #expect(await rig.waitForPosts(1))
    #expect(await rig.waitForSleepers(Self.sleepers))
    await rig.settle()
    await send(.screensDidSleep, rig)
    // Ten intervals pass; the budget is three.
    await rig.advance(600)
    #expect(await rig.poster.posted.count == 1)
    await send(.screensDidWake, rig)
    #expect(await rig.waitForPosts(2))
    for posts in 3...5 {
      #expect(await rig.waitForSleepers(Self.sleepers))
      await rig.settle()
      await rig.advance(60)
      #expect(await rig.waitForPosts(posts))
    }
    await rig.advance(600)
    #expect(await rig.poster.posted.count == 5)
    await rig.service.shutdown()
  }

  @Test func aMessagePostedWhileAwayIsPostedAgainOnReturnBeforeItsFirstTick() async throws {
    let rig = await rig()
    await send(.screensDidSleep, rig)
    try await rig.receive("u", priority: 5, sequence: "s")
    #expect(await rig.waitForPosts(1))
    await send(.screensDidWake, rig)
    await rig.advance(1.5)
    #expect(await rig.waitForPosts(2))
    #expect(await rig.poster.postedIdentifiers == ["t/s", "t/s"])
    await rig.service.shutdown()
  }

  @Test func theSystemGoingToSleepCountsAsAway() async throws {
    let rig = await rig()
    try await rig.receive("u", priority: 5, sequence: "s")
    #expect(await rig.waitForPosts(1))
    await send(.willSleep, rig)
    await rig.advance(600)
    await send(.didWake, rig)
    #expect(await rig.poster.posted.count == 1)
    await send(.screensDidWake, rig)
    #expect(await rig.waitForPosts(2))
    await rig.service.shutdown()
  }

  @Test func aDarkWakeAloneDoesNotBringAnyoneBack() async throws {
    let rig = await rig()
    try await rig.receive("u", priority: 5, sequence: "s")
    #expect(await rig.waitForPosts(1))
    await send(.screensDidSleep, rig)
    await rig.advance(120)
    await send(.didWake, rig)
    await rig.advance(120)
    #expect(await rig.poster.posted.count == 1)
    await rig.service.shutdown()
  }

  @Test func aMessageAcknowledgedWhileAwayIsNotPostedAgain() async throws {
    let rig = await rig()
    try await rig.receive("u", priority: 5, sequence: "s")
    #expect(await rig.waitForPosts(1))
    await send(.screensDidSleep, rig)
    await rig.advance(120)
    await rig.service.acknowledge(topic: "t", id: "u")
    await send(.screensDidWake, rig)
    await rig.settle()
    #expect(await rig.poster.posted.count == 1)
    await rig.service.shutdown()
  }

  @Test func aMessageBelowTheReAlertThresholdIsNotPostedAgainOnReturn() async throws {
    let rig = await rig()
    await send(.screensDidSleep, rig)
    try await rig.receive("n", priority: 3)
    #expect(await rig.waitForPosts(1))
    await send(.screensDidWake, rig)
    await rig.settle()
    #expect(await rig.poster.posted.count == 1)
    await rig.service.shutdown()
  }

  @Test func withoutAnyoneAwayTheChainRunsAsBefore() async throws {
    let rig = await rig()
    try await rig.receive("u", priority: 5, sequence: "s")
    #expect(await rig.waitForPosts(1))
    #expect(await rig.waitForSleepers(Self.sleepers))
    await rig.settle()
    await rig.advance(60)
    #expect(await rig.waitForPosts(2))
    await send(.screensDidWake, rig)
    await rig.settle()
    #expect(await rig.poster.posted.count == 2)
    await rig.service.shutdown()
  }

  @Test func turningReAlertOffWhileAwayPostsNothingOnReturn() async throws {
    let rig = await rig()
    try await rig.receive("u", priority: 5, sequence: "s")
    #expect(await rig.waitForPosts(1))
    await send(.screensDidSleep, rig)
    await rig.advance(120)
    await rig.config.save(Config(dismiss: [5: 0], reAlert: false))
    await send(.screensDidWake, rig)
    await rig.settle()
    #expect(await rig.poster.posted.count == 1)
    await rig.service.shutdown()
  }
}

private let hour: TimeInterval = 3600

/// A catch-up after a long absence must still show what has to be acknowledged.
@Suite struct DeliveryUrgentCatchUpTests {
  private static let config = Config(
    dismiss: [1: 0, 2: 0, 3: 0, 4: 0, 5: 0], reAlertIntervalSeconds: 60, reAlertMaxRepeats: 3)

  @Test func anUrgentMessageIsNotSilencedByTheAgeOfTheBatch() async throws {
    let rig = DeliveryRig(config: Self.config)
    let urgent = rig.message("u", priority: 5, age: 20 * hour)
    let old = rig.message("old", age: 40 * hour)
    for message in [old, urgent] { try await rig.history.append(message) }
    await rig.service.announceMissed([old, urgent])
    #expect(await rig.waitForPosts(1))
    #expect(await rig.poster.postedIDs == ["u"])
    await rig.settle()
    #expect(await rig.poster.summaries.isEmpty)
    #expect(await rig.history.unnotified(limit: 10, offset: 0).isEmpty)
    await rig.service.shutdown()
  }

  @Test func theRestOfTheBatchStillFollowsItsAge() async throws {
    let rig = DeliveryRig(config: Self.config)
    let urgent = rig.message("u", priority: 5, age: 20 * hour)
    let others = (0..<2).map { rig.message("m\($0)", age: 3 * hour) }
    for message in [urgent] + others { try await rig.history.append(message) }
    await rig.service.announceMissed([urgent] + others)
    #expect(await rig.waitForPosts(1))
    // The pacing sleep and the urgent message's re-alert timer.
    #expect(await rig.waitForSleepers(2))
    await rig.advance(1.5)
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    #expect(await rig.poster.summaries == [.init(count: 2, oldestTopic: "t")])
    #expect(await rig.poster.postedIDs == ["u"])
    await rig.service.shutdown()
  }

  @Test func anUrgentMessageStartsItsReAlertChain() async throws {
    let rig = DeliveryRig(config: Self.config)
    let urgent = rig.message("u", priority: 5, age: 5 * hour)
    try await rig.history.append(urgent)
    await rig.service.announceMissed([urgent])
    #expect(await rig.waitForPosts(1))
    #expect(await rig.waitForSleepers(1))
    await rig.settle()
    await rig.advance(60)
    #expect(await rig.waitForPosts(2))
    await rig.service.shutdown()
  }

  @Test func anUrgentMessageOlderThanAdayStaysQuiet() async throws {
    let rig = DeliveryRig(config: Self.config)
    let urgent = rig.message("u", priority: 5, age: 30 * hour)
    try await rig.history.append(urgent)
    await rig.service.announceMissed([urgent])
    await rig.settle()
    #expect(await rig.poster.attempts == 0)
    await rig.service.shutdown()
  }

  @Test func withReAlertOffNothingIsMustAcknowledge() async throws {
    let rig = DeliveryRig(config: Config(reAlert: false))
    let urgent = rig.message("u", priority: 5, age: 20 * hour)
    try await rig.history.append(urgent)
    await rig.service.announceMissed([urgent])
    await rig.settle()
    #expect(await rig.poster.attempts == 0)
    await rig.service.shutdown()
  }
}
