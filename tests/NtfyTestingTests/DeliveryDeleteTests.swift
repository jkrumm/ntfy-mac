import Foundation
import NtfyCore
import NtfyTesting
import Testing

@Suite struct DeliveryDeleteTests {
  @Test func deletingAShownMessageHidesItsSequenceAndRemovesTheNotification() async throws {
    let rig = DeliveryRig()
    try await rig.receive("a", sequence: "s")
    #expect(await rig.waitForPosts(1))
    #expect(await rig.service.delete(topic: "t", id: "a"))
    #expect(await rig.poster.removed == ["t/s"])
    #expect(await rig.history.recent(limit: 10).isEmpty)
    #expect(await rig.history.message(topic: "t", id: "a") == nil)
    await rig.service.shutdown()
  }

  @Test func deletingStopsTheDismissTimerAndTheReAlerts() async throws {
    let rig = DeliveryRig(
      config: Config(
        dismiss: [5: 0], reAlert: true, reAlertIntervalSeconds: 60, reAlertMaxRepeats: 3))
    try await rig.receive("u", priority: 5)
    #expect(await rig.waitForPosts(1))
    #expect(await rig.waitForSleepers(1))
    #expect(await rig.service.delete(topic: "t", id: "u"))
    #expect(rig.clock.sleeperCount == 0)
    await rig.advance(600)
    #expect(await rig.poster.posted.count == 1)
    await rig.service.shutdown()
  }

  @Test func deletingAQueuedMessageDropsItBeforeItIsShown() async throws {
    let rig = DeliveryRig()
    try await rig.occupyTheSlot()
    try await rig.receive("queued")
    #expect(await rig.service.delete(topic: "t", id: "queued"))
    await rig.nextSlot()
    await rig.settle()
    #expect(await rig.poster.postedIDs == ["blocker"])
    await rig.service.shutdown()
  }

  @Test func deletingAnUnknownMessageReportsFalseAndChangesNothing() async throws {
    let rig = DeliveryRig()
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    #expect(await rig.service.delete(topic: "t", id: "missing") == false)
    #expect(await rig.service.delete(topic: "other", id: "a") == false)
    #expect(await rig.poster.removed.isEmpty)
    #expect(await rig.history.recent(limit: 10).count == 1)
    await rig.service.shutdown()
  }

  @Test func aDeletedMessageDoesNotComeBackThroughAReminder() async throws {
    let rig = DeliveryRig()
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    await rig.history.snooze(topic: "t", id: "a", until: rig.clock.now().addingTimeInterval(60))
    #expect(await rig.service.delete(topic: "t", id: "a"))
    #expect(await rig.history.dueReminders(now: rig.clock.now().addingTimeInterval(120)).isEmpty)
    await rig.service.shutdown()
  }

  @Test func deleteAllRemovesEveryMessageOfTheTopicOnly() async throws {
    let rig = DeliveryRig()
    for id in ["a", "b", "c"] { try await rig.history.append(rig.message(id)) }
    try await rig.history.append(rig.message("a", topic: "keep"))
    try await rig.history.append(rig.message("d", sequence: "c"))
    #expect(await rig.service.deleteAll(topic: "t") == 3)
    #expect(await rig.history.entries(HistoryQuery(topic: "t")).isEmpty)
    #expect(await rig.history.entries(HistoryQuery(topic: "keep")).count == 1)
    #expect(await rig.poster.removed.sorted() == ["t/a", "t/b", "t/c"])
    #expect(await rig.service.deleteAll(topic: "t") == 0)
    await rig.service.shutdown()
  }
}
