import Foundation
import NtfyCore
import NtfyTesting
import Testing

/// The rig's clock starts at 22:13 UTC, inside a default 22:00-07:00 window.
@Suite struct DeliveryQuietHoursTests {
  private func rig(digest: Bool = true, bypass: Bool = true) -> DeliveryRig {
    var config = Config.withoutTimers
    config.quietHours = QuietHours(enabled: true, urgentBypass: bypass, digest: digest)
    return DeliveryRig(config: config)
  }

  private func unnotifiedCount(_ rig: DeliveryRig) async -> Int {
    await rig.history.unnotified(limit: 10, offset: 0).count
  }

  @Test func aMessageInsideTheWindowIsStoredButNotPosted() async throws {
    let rig = rig()
    try await rig.receive("a")
    await rig.settle()
    #expect(await rig.poster.attempts == 0)
    #expect(await unnotifiedCount(rig) == 1)
    await rig.service.shutdown()
  }

  @Test func aMessageOutsideTheWindowIsPosted() async throws {
    let rig = rig()
    await rig.advance(rig.untilMorning + 60)
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    await rig.service.shutdown()
  }

  @Test func aDisabledScheduleHoldsNothing() async throws {
    let rig = rig()
    await rig.config.update { $0.quietHours.enabled = false }
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    await rig.service.shutdown()
  }

  @Test func priorityFiveBypassesTheWindowWhenAsked() async throws {
    let rig = rig()
    try await rig.receive("calm", priority: 4)
    try await rig.receive("urgent", priority: 5)
    #expect(await rig.waitForPosts(1))
    #expect(await rig.poster.postedIDs == ["urgent"])
    await rig.service.shutdown()
  }

  @Test func withoutTheBypassPriorityFiveIsHeldToo() async throws {
    let rig = rig(bypass: false)
    try await rig.receive("urgent", priority: 5)
    await rig.settle()
    #expect(await rig.poster.attempts == 0)
    await rig.service.shutdown()
  }

  @Test func theEndOfTheWindowAnnouncesWhatWasHeldAsOneSummary() async throws {
    let rig = rig()
    try await rig.receive("a", topic: "first")
    try await rig.receive("b", topic: "second")
    try await rig.receive("c", topic: "second")
    await rig.settle()
    await rig.advance(rig.untilMorning + 1)
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    #expect(await rig.poster.summaries.first?.count == 3)
    #expect(await rig.poster.summaries.first?.oldestTopic == "first")
    #expect(await rig.poster.posted.isEmpty)
    #expect(await rig.eventually { await unnotifiedCount(rig) == 0 })
    await rig.service.shutdown()
  }

  @Test func withoutADigestTheHeldMessagesGoOutOneByOneWhateverTheirAge() async throws {
    let rig = rig(digest: false)
    try await rig.receive("a")
    try await rig.receive("b")
    await rig.settle()
    await rig.advance(rig.untilMorning + 1)
    #expect(await rig.waitForPosts(1))
    await rig.nextSlot()
    #expect(await rig.waitForPosts(2))
    #expect(await rig.poster.postedIDs == ["a", "b"])
    #expect(await rig.poster.summaries.isEmpty)
    await rig.service.shutdown()
  }

  @Test func theDigestSettingIsReadWhenTheWindowEnds() async throws {
    let rig = rig(digest: true)
    try await rig.receive("a")
    try await rig.receive("b")
    await rig.settle()
    await rig.config.update { $0.quietHours.digest = false }
    await rig.advance(rig.untilMorning + 1)
    #expect(await rig.waitForPosts(1))
    #expect(await rig.poster.summaries.isEmpty)
    await rig.service.shutdown()
  }

  @Test func aPauseThatOutlastsTheWindowWinsAndOneReconcileFollows() async throws {
    let rig = rig()
    try await rig.receive("a")
    await rig.settle()
    let morning = rig.untilMorning
    await rig.config.update { $0.pausedUntil = rig.clock.now().addingTimeInterval(morning + 3600) }
    try await rig.receive("b")
    await rig.settle()
    await rig.advance(morning + 60)
    #expect(await rig.poster.attempts == 0)
    await rig.advance(3600)
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    #expect(await rig.poster.summaries.first?.count == 2)
    await rig.service.shutdown()
  }

  @Test func aPauseThatEndsInsideTheWindowLeavesTheWindowInForce() async throws {
    let rig = rig()
    await rig.config.update { $0.pausedUntil = rig.clock.now().addingTimeInterval(600) }
    try await rig.receive("a")
    await rig.settle()
    await rig.advance(700)
    #expect(await rig.poster.attempts == 0)
    await rig.advance(rig.untilMorning + 1)
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    await rig.service.shutdown()
  }

  @Test func extendingTheWindowReArmsTheEnd() async throws {
    let rig = rig()
    try await rig.receive("a")
    await rig.settle()
    let originalEnd = rig.untilMorning
    let nine = try #require(ClockTime(hour: 9, minute: 0))
    await rig.config.update { $0.quietHours.end = nine }
    await rig.advance(originalEnd + 60)
    #expect(await rig.poster.attempts == 0)
    await rig.advance(2 * 3600)
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    await rig.service.shutdown()
  }

  @Test func disablingTheWindowReleasesAtTheNextReminderPoll() async throws {
    let rig = rig(digest: false)
    try await rig.receive("a")
    await rig.settle()
    await rig.service.start()
    #expect(await rig.waitForSleepers(2))
    await rig.config.update { $0.quietHours.enabled = false }
    await rig.advance(31)
    #expect(await rig.waitForPosts(1))
    await rig.service.shutdown()
  }

  @Test func aLocalMessageIgnoresTheWindow() async throws {
    let rig = rig()
    let message = rig.message("l1", topic: "local")
    try await rig.history.append(message)
    await rig.service.deliverLocal(message, dismissAfter: nil)
    #expect(await rig.waitForPosts(1))
    await rig.service.shutdown()
  }

  @Test func aLocalMessageIsStillHeldByAManualPause() async throws {
    let rig = rig()
    await rig.config.update { $0.pausedUntil = rig.clock.now().addingTimeInterval(600) }
    let message = rig.message("l1", topic: "local")
    try await rig.history.append(message)
    await rig.service.deliverLocal(message, dismissAfter: nil)
    await rig.settle()
    #expect(await rig.poster.attempts == 0)
    await rig.service.shutdown()
  }

  @Test func aBootReconcileInsideTheWindowHoldsTheSummaryToo() async throws {
    let rig = rig()
    for index in 0..<3 {
      try await rig.history.append(rig.message("m\(index)", age: 3 * 3600 - Double(index)))
    }
    await rig.service.reconcile()
    await rig.settle()
    #expect(await rig.poster.summaries.isEmpty)
    #expect(await unnotifiedCount(rig) == 3)
    await rig.advance(rig.untilMorning + 1)
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    await rig.service.shutdown()
  }
}
