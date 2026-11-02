import Foundation
import NtfyCore
import NtfyTesting
import Testing

private let hour: TimeInterval = 3600

@Suite struct DeliveryReconcileUnnotifiedTests {
  private func store(_ rig: DeliveryRig, _ messages: [NtfyMessage]) async throws {
    for message in messages { try await rig.history.append(message) }
  }

  @Test func messagesWithinAnHourAreShownIndividually() async throws {
    let rig = DeliveryRig()
    try await store(rig, [rig.message("a", age: 10 * 60), rig.message("b", age: 5 * 60)])
    await rig.service.reconcile()
    #expect(await rig.waitForPosts(1))
    await rig.nextSlot()
    #expect(await rig.waitForPosts(2))
    #expect(await rig.poster.postedIDs == ["a", "b"])
    #expect(await rig.eventually { await rig.history.unnotified(limit: 10, offset: 0).isEmpty })
    await rig.service.shutdown()
  }

  @Test func messagesUpToTwelveHoursOldBecomeOneSummary() async throws {
    let rig = DeliveryRig()
    try await store(rig, (0..<3).map { rig.message("m\($0)", age: 3 * hour - Double($0)) })
    await rig.service.reconcile()
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    #expect(await rig.poster.summaries == [.init(count: 3, oldestTopic: "t")])
    #expect(await rig.poster.posted.isEmpty)
    #expect(await rig.eventually { await rig.history.unnotified(limit: 10, offset: 0).isEmpty })
    await rig.service.shutdown()
  }

  @Test func olderMessagesAreSkippedButNotReconsideredForever() async throws {
    let rig = DeliveryRig()
    try await store(rig, [rig.message("old", age: 13 * hour)])
    await rig.service.reconcile()
    await rig.settle()
    #expect(await rig.poster.attempts == 0)
    #expect(await rig.history.unnotified(limit: 10, offset: 0).isEmpty)
    await rig.service.shutdown()
  }

  @Test func aSummaryThatCouldNotBePostedLeavesTheMessagesForTheNextBoot() async throws {
    let rig = DeliveryRig()
    try await store(rig, [rig.message("a", age: 3 * hour), rig.message("b", age: 2 * hour)])
    await rig.poster.failNext(1)
    await rig.service.reconcile()
    #expect(await rig.waitForAttempts(1))
    await rig.settle()
    #expect(await rig.history.unnotified(limit: 10, offset: 0).count == 2)
    await rig.service.shutdown()
  }

  @Test func aMessageAlreadyQueuedIsNotAnnouncedTwice() async throws {
    let rig = DeliveryRig()
    try await rig.occupyTheSlot()
    try await rig.receive("queued")
    await rig.service.reconcile()
    await rig.nextSlot()
    #expect(await rig.waitForPosts(2))
    await rig.nextSlot()
    await rig.settle()
    #expect(await rig.poster.postedIDs == ["blocker", "queued"])
    await rig.service.shutdown()
  }
}

@Suite struct DeliveryReconcileResumeTests {
  private static let config = Config(
    dismiss: [3: 0, 5: 0], reAlertIntervalSeconds: 60, reAlertMaxRepeats: 2)

  private func shown(_ rig: DeliveryRig, _ message: NtfyMessage, ago: TimeInterval) async throws {
    try await rig.history.append(message)
    await rig.history.markNotified(
      topic: message.topic, id: message.id, at: rig.clock.now().addingTimeInterval(-ago))
  }

  @Test func unacknowledgedUrgentMessagesResumeReAlerting() async throws {
    let rig = DeliveryRig(config: Self.config)
    try await shown(rig, rig.message("open", priority: 5, age: 300), ago: 300)
    try await shown(rig, rig.message("done", priority: 5, age: 300), ago: 300)
    try await shown(rig, rig.message("minor", priority: 3, age: 300), ago: 300)
    await rig.history.acknowledge(topic: "t", id: "done")
    await rig.service.reconcile()
    #expect(await rig.waitForSleepers(1))
    await rig.advance(60)
    #expect(await rig.waitForPosts(1))
    #expect(await rig.poster.postedIDs == ["open"])
    #expect(await rig.waitForSleepers(1))
    await rig.advance(60)
    #expect(await rig.waitForPosts(2))
    await rig.settle()
    #expect(rig.clock.sleeperCount == 0)
    await rig.service.shutdown()
  }

  @Test func onlyMessagesYoungerThanADayResume() async throws {
    let rig = DeliveryRig(config: Self.config)
    try await shown(rig, rig.message("old", priority: 5, age: 25 * hour), ago: 25 * hour)
    await rig.service.reconcile()
    await rig.settle()
    #expect(rig.clock.sleeperCount == 0)

    try await shown(rig, rig.message("recent", priority: 5, age: 23 * hour), ago: 23 * hour)
    await rig.service.reconcile()
    #expect(await rig.waitForSleepers(1))
    await rig.advance(60)
    #expect(await rig.waitForPosts(1))
    #expect(await rig.poster.postedIDs == ["recent"])
    #expect(await rig.history.unacknowledged(minPriority: .max).count == 2)
    await rig.service.shutdown()
  }

  @Test func nothingResumesWhileReAlertIsOff() async throws {
    var config = Self.config
    config.reAlert = false
    let rig = DeliveryRig(config: config)
    try await shown(rig, rig.message("open", priority: 5, age: 300), ago: 300)
    await rig.service.reconcile()
    await rig.settle()
    #expect(rig.clock.sleeperCount == 0)
    await rig.service.shutdown()
  }
}

@Suite struct DeliveryReconcileDismissTests {
  private func shown(_ rig: DeliveryRig, _ id: String, priority: Int = 3, ago: TimeInterval)
    async throws
  {
    let message = rig.message(id, priority: priority, age: ago)
    try await rig.history.append(message)
    await rig.history.markNotified(
      topic: "t", id: id, at: rig.clock.now().addingTimeInterval(-ago))
  }

  @Test func notificationsPastTheirDismissTimeAreRemovedAndTheRestFollow() async throws {
    let rig = DeliveryRig(config: Config(reAlert: false))
    try await shown(rig, "expired", ago: 20)
    try await shown(rig, "fresh", ago: 3)
    try await shown(rig, "sticky", priority: 4, ago: 3600)
    await rig.poster.setDelivered(["t/expired", "t/fresh", "t/sticky", "t/other-app"])
    await rig.service.reconcile()
    #expect(await rig.poster.removed == ["t/expired"])
    #expect(await rig.waitForSleepers(1))
    await rig.advance(4.9)
    #expect(await rig.poster.removed == ["t/expired"])
    await rig.advance(0.1)
    #expect(await rig.eventually { await rig.poster.removed == ["t/expired", "t/fresh"] })
    await rig.service.shutdown()
  }

  @Test func aNotificationThatIsNotShownAnymoreIsLeftAlone() async throws {
    let rig = DeliveryRig(config: Config(reAlert: false))
    try await shown(rig, "gone", ago: 20)
    await rig.service.reconcile()
    #expect(await rig.poster.removed.isEmpty)
    await rig.service.shutdown()
  }
}

@Suite struct DeliveryReconcilePagingTests {
  @Test func moreThanOnePageOfUnnotifiedMessagesIsAnnouncedAsOneBatch() async throws {
    let rig = DeliveryRig()
    let count = 1_050
    for index in 0..<count {
      try await rig.history.append(rig.message("m\(index)", age: 3 * hour - Double(index) / 1000))
    }
    await rig.service.reconcile()
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    #expect(await rig.poster.summaries == [.init(count: count, oldestTopic: "t")])
    #expect(await rig.eventually { await rig.history.unnotified(limit: 10, offset: 0).isEmpty })
    await rig.service.shutdown()
  }

  @Test func expiryLookupFindsADeliveredNotificationBeyondTheFirstPage() async throws {
    let rig = DeliveryRig(config: Config(reAlert: false))
    let now = rig.clock.now()
    try await rig.history.append(rig.message("old", age: 20))
    await rig.history.markNotified(topic: "t", id: "old", at: now.addingTimeInterval(-20))
    for index in 0..<(1_005) {
      try await rig.history.append(rig.message("n\(index)"))
    }
    await rig.poster.setDelivered(["t/old"])
    await rig.service.reconcile()
    #expect(await rig.poster.removed == ["t/old"])
    await rig.service.shutdown()
  }
}

@Suite struct DeliveryReminderTests {
  private func dueReminder(_ rig: DeliveryRig) async throws {
    try await rig.history.append(rig.message("a", age: 600))
    await rig.history.markNotified(topic: "t", id: "a", at: rig.clock.now())
    await rig.history.snooze(topic: "t", id: "a", until: rig.clock.now().addingTimeInterval(-1))
  }

  private func stillDue(_ rig: DeliveryRig) async -> Bool {
    await !rig.history.dueReminders(now: rig.clock.now().addingTimeInterval(3600)).isEmpty
  }

  @Test func aFailedPostLeavesTheReminderDueUntilALaterTickShowsIt() async throws {
    let rig = DeliveryRig()
    try await dueReminder(rig)
    await rig.poster.failNext(3)
    await rig.service.reconcile()
    for attempts in 1...3 {
      #expect(await rig.waitForAttempts(attempts))
      await rig.nextSlot()
    }
    await rig.settle()
    #expect(await rig.poster.posted.isEmpty)
    #expect(await stillDue(rig))

    await rig.service.start()
    #expect(await rig.waitForSleepers(1))
    await rig.advance(30)
    #expect(await rig.waitForPosts(1))
    #expect(await rig.eventually { await !stillDue(rig) })
    await rig.service.shutdown()
  }

  @Test func aReminderQueuedAlreadyIsNotQueuedAgainByTheNextTick() async throws {
    let rig = DeliveryRig()
    try await dueReminder(rig)
    await rig.poster.failNext(1)
    await rig.service.reconcile()
    #expect(await rig.waitForAttempts(1))
    await rig.service.start()
    await rig.advance(30)
    #expect(await rig.waitForPosts(1))
    await rig.settle()
    #expect(await rig.poster.attempts == 2)
    await rig.service.shutdown()
  }

  @Test func aReminderThatCannotBeClearedIsShownOnceAndClearedLater() async throws {
    let rig = DeliveryRig()
    try await dueReminder(rig)
    await rig.history.setClearReminderFailure(.storage("locked"))
    await rig.service.reconcile()
    #expect(await rig.waitForPosts(1))
    await rig.service.start()
    for _ in 0..<3 {
      #expect(await rig.waitForSleepers(1))
      await rig.advance(30)
    }
    #expect(await rig.poster.posted.count == 1)
    #expect(await stillDue(rig))

    await rig.history.setClearReminderFailure(nil)
    #expect(await rig.waitForSleepers(1))
    await rig.advance(30)
    #expect(await rig.eventually { await !stillDue(rig) })
    #expect(await rig.poster.posted.count == 1)
    await rig.service.shutdown()
  }

  @Test func aReminderThatIsAlreadyDueFiresDuringReconcile() async throws {
    let rig = DeliveryRig()
    let message = rig.message("a", age: 600)
    try await rig.history.append(message)
    await rig.history.markNotified(topic: "t", id: "a", at: rig.clock.now())
    await rig.history.snooze(topic: "t", id: "a", until: rig.clock.now().addingTimeInterval(-1))
    await rig.service.reconcile()
    #expect(await rig.waitForPosts(1))
    #expect(await rig.poster.postedIDs == ["a"])
    #expect(await rig.history.dueReminders(now: rig.clock.now().addingTimeInterval(3600)).isEmpty)
    await rig.service.shutdown()
  }

  @Test func theReminderPollFiresWhenTheTimeComes() async throws {
    let rig = DeliveryRig()
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    await rig.history.snooze(topic: "t", id: "a", until: rig.clock.now().addingTimeInterval(45))
    await rig.service.start()
    #expect(await rig.waitForSleepers(1))
    await rig.advance(30)
    await rig.settle()
    #expect(await rig.poster.posted.count == 1)
    #expect(await rig.waitForSleepers(1))
    await rig.advance(30)
    #expect(await rig.waitForPosts(2))
    #expect(await rig.poster.postedIDs == ["a", "a"])
    // Fired once: the poll keeps running, the reminder is gone.
    await rig.advance(30)
    await rig.settle()
    #expect(await rig.poster.posted.count == 2)
    await rig.service.shutdown()
    #expect(rig.clock.sleeperCount == 0)
  }

  @Test func startingTwiceKeepsOnePoll() async throws {
    let rig = DeliveryRig()
    await rig.service.start()
    await rig.service.start()
    #expect(await rig.waitForSleepers(1))
    await rig.settle()
    #expect(rig.clock.sleeperCount == 1)
    await rig.service.shutdown()
  }
}
