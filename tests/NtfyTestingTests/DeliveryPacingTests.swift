import Foundation
import NtfyCore
import NtfyTesting
import Testing

@Suite struct DeliveryPacingTests {
  @Test func theFirstPostIsImmediate() async throws {
    let rig = DeliveryRig()
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    #expect(await rig.poster.postedIDs == ["a"])
    await rig.service.shutdown()
  }

  @Test func aBurstDrainsByPriorityThenArrival() async throws {
    let rig = DeliveryRig()
    try await rig.occupyTheSlot()
    try await rig.receive("low", priority: 1)
    try await rig.receive("urgent", priority: 5)
    try await rig.receive("first", priority: 3)
    try await rig.receive("second", priority: 3)
    for posts in 2...5 {
      await rig.nextSlot()
      #expect(await rig.waitForPosts(posts))
    }
    #expect(await rig.poster.postedIDs == ["blocker", "urgent", "first", "second", "low"])
    await rig.service.shutdown()
  }

  @Test func postsAreAtLeastOneAndAHalfSecondsApart() async throws {
    let rig = DeliveryRig()
    try await rig.occupyTheSlot()
    try await rig.receive("next")
    #expect(await rig.waitForSleepers(1))
    await rig.advance(1.4)
    #expect(await rig.poster.posted.count == 1)
    await rig.advance(0.1)
    #expect(await rig.waitForPosts(2))
    await rig.service.shutdown()
  }

  @Test func anIdleServiceHoldsNoTimer() async throws {
    let rig = DeliveryRig()
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    await rig.settle()
    #expect(rig.clock.sleeperCount == 0)
    await rig.service.shutdown()
  }

  @Test func contentIsBuiltWithTheConfigOfPostTime() async throws {
    let rig = DeliveryRig()
    try await rig.occupyTheSlot()
    try await rig.receive("late")
    await rig.config.update { $0.sounds[3] = .named("Glass") }
    await rig.nextSlot()
    #expect(await rig.waitForPosts(2))
    #expect(await rig.poster.posted.last?.sound == "Glass")
    await rig.service.shutdown()
  }
}

@Suite struct DeliveryRetryTests {
  @Test func aFailedPostIsRetriedAndSucceedsTheSecondTime() async throws {
    let rig = DeliveryRig()
    await rig.poster.failNext(1)
    try await rig.receive("a")
    #expect(await rig.waitForAttempts(1))
    #expect(await rig.poster.posted.isEmpty)
    await rig.nextSlot()
    #expect(await rig.waitForPosts(1))
    #expect(await rig.poster.attempts == 2)
    await rig.service.shutdown()
  }

  @Test func theThirdFailureGivesUpAndLeavesTheMessageUnnotified() async throws {
    let rig = DeliveryRig()
    await rig.poster.failNext(5)
    try await rig.receive("a")
    for attempts in 1...3 {
      #expect(await rig.waitForAttempts(attempts))
      await rig.nextSlot()
    }
    await rig.settle()
    #expect(await rig.poster.attempts == 3)
    #expect(await rig.poster.posted.isEmpty)
    #expect(rig.clock.sleeperCount == 0)
    #expect(await rig.history.unnotified(limit: 10, offset: 0).map(\.id) == ["a"])
    await rig.service.shutdown()
  }

  @Test func aSummaryIsTriedOnce() async throws {
    let rig = DeliveryRig()
    await rig.poster.failNext(1)
    let batch = [rig.message("a", age: 3 * 3600), rig.message("b", age: 3 * 3600 - 1)]
    for message in batch { try await rig.history.append(message) }
    await rig.service.announceMissed(batch)
    #expect(await rig.waitForAttempts(1))
    await rig.settle()
    #expect(await rig.poster.attempts == 1)
    #expect(await rig.poster.summaries.isEmpty)
    #expect(rig.clock.sleeperCount == 0)
    #expect(await rig.history.unnotified(limit: 10, offset: 0).count == 2)
    await rig.service.shutdown()
  }

  @Test func aRetryReturnsToItsPlaceAheadOfLaterPeersButBehindUrgentOnes() async throws {
    let rig = DeliveryRig()
    await rig.poster.failNext(1)
    try await rig.receive("a")
    #expect(await rig.waitForAttempts(1))
    try await rig.receive("b")
    try await rig.receive("urgent", priority: 5)
    for posts in 1...3 {
      await rig.nextSlot()
      #expect(await rig.waitForPosts(posts))
    }
    #expect(await rig.poster.postedIDs == ["urgent", "a", "b"])
    await rig.service.shutdown()
  }

  @Test func aMessageCountsAsNotifiedOnlyAfterASuccessfulPost() async throws {
    let rig = DeliveryRig()
    await rig.poster.failNext(1)
    try await rig.receive("a")
    #expect(await rig.waitForAttempts(1))
    await rig.settle()
    #expect(await rig.history.unnotified(limit: 10, offset: 0).map(\.id) == ["a"])
    await rig.nextSlot()
    #expect(await rig.waitForPosts(1))
    #expect(await rig.eventually { await rig.history.unnotified(limit: 10, offset: 0).isEmpty })
    await rig.service.shutdown()
  }

  @Test func aPosterThatAlwaysFailsNeitherThrowsNorBlocksTheResponses() async throws {
    let rig = DeliveryRig(poster: RecordingNotificationPoster(failingWith: .permissionDenied))
    try await rig.receive("a")
    #expect(await rig.waitForAttempts(1))
    await rig.service.acknowledge(topic: "t", id: "a")
    await rig.service.withdraw(topic: "t", sequenceID: "a")
    await rig.service.clear(topic: "t", sequenceID: "a")
    await rig.service.reconcile()
    await rig.service.shutdown()
    #expect(await rig.poster.posted.isEmpty)
  }
}

@Suite struct DeliveryShutdownTests {
  @Test func shutdownLeavesNoTaskOnTheClock() async throws {
    let rig = DeliveryRig(config: Config(reAlertIntervalSeconds: 60))
    await rig.service.start()
    try await rig.receive("urgent", priority: 5)
    try await rig.receive("queued", priority: 3)
    #expect(await rig.waitForPosts(1))
    // The reminder poll, the re-alert timer, and the drain waiting for its slot.
    #expect(await rig.waitForSleepers(3))
    await rig.service.shutdown()
    #expect(rig.clock.sleeperCount == 0)
    await rig.advance(600)
    #expect(await rig.poster.posted.count == 1)
  }

  @Test func shutdownIsIdempotentAndStopsAcceptingMessages() async throws {
    let rig = DeliveryRig()
    await rig.service.shutdown()
    await rig.service.shutdown()
    try await rig.receive("late")
    await rig.settle()
    #expect(await rig.poster.attempts == 0)
    #expect(rig.clock.sleeperCount == 0)
  }
}
