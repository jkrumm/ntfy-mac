import Foundation
import NtfyCore
import NtfyTesting
import Testing

@Suite struct DeliveryMeetingTests {
  private let zoom = MeetingState.active(.app("Zoom"))

  private func rig(
    mode: MeetingMode = .pause, bypass: Bool = true, state: MeetingState? = nil,
    presentingFor: TimeInterval? = nil
  ) async -> (rig: DeliveryRig, meeting: ManualMeetingState) {
    let meeting = ManualMeetingState(state ?? zoom)
    let rig = DeliveryRig(meeting: meeting)
    let now = rig.clock.now()
    await rig.config.update {
      $0.meeting = MeetingSettings(
        mode: mode, urgentBypass: bypass,
        presentingUntil: presentingFor.map { now.addingTimeInterval($0) })
    }
    await rig.service.start()
    return (rig, meeting)
  }

  private func unnotified(_ rig: DeliveryRig) async -> Int {
    await rig.history.unnotified(limit: 10, offset: 0).count
  }

  @Test func aMessageDuringAMeetingIsStoredButNotPosted() async throws {
    let (rig, _) = await rig()
    try await rig.receive("a")
    await rig.settle()
    #expect(await rig.poster.attempts == 0)
    #expect(await unnotified(rig) == 1)
    await rig.service.shutdown()
  }

  @Test func modeOffIgnoresTheDetection() async throws {
    let (rig, _) = await rig(mode: .off)
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    await rig.service.shutdown()
  }

  @Test func noMeetingMeansNormalDelivery() async throws {
    let (rig, _) = await rig(state: .inactive)
    try await rig.receive("a")
    #expect(await rig.waitForPosts(1))
    await rig.service.shutdown()
  }

  @Test func theEndOfTheMeetingAnnouncesWhatWasHeldAsOneMeetingSummary() async throws {
    let (rig, meeting) = await rig()
    try await rig.receive("a")
    try await rig.receive("b", priority: 4)
    try await rig.receive("c")
    await rig.settle()
    #expect(await rig.poster.attempts == 0)
    meeting.set(.inactive)
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    let summary = await rig.poster.summaries.first
    #expect(summary?.count == 3)
    #expect(summary?.cause == .meeting)
    #expect(await rig.poster.posted.isEmpty)
    #expect(await rig.eventually { await unnotified(rig) == 0 })
    await rig.service.shutdown()
  }

  @Test func aMeetingWithNothingHeldPostsNothingWhenItEnds() async throws {
    let (rig, meeting) = await rig()
    await rig.settle()
    meeting.set(.inactive)
    await rig.settle()
    #expect(await rig.poster.summaries.isEmpty)
    #expect(await rig.poster.attempts == 0)
    await rig.service.shutdown()
  }

  @Test func priorityFiveBypassesAMeetingWhenAsked() async throws {
    let (rig, _) = await rig()
    try await rig.receive("calm", priority: 4)
    try await rig.receive("urgent", priority: 5)
    #expect(await rig.waitForPosts(1))
    #expect(await rig.poster.postedIDs == ["urgent"])
    await rig.service.shutdown()
  }

  @Test func withoutTheBypassPriorityFiveIsHeldToo() async throws {
    let (rig, _) = await rig(bypass: false)
    try await rig.receive("urgent", priority: 5)
    await rig.settle()
    #expect(await rig.poster.attempts == 0)
    await rig.service.shutdown()
  }

  @Test func aLocalMessageIsNotHeldByAMeeting() async throws {
    let (rig, _) = await rig()
    let message = rig.message("local")
    try await rig.history.append(message)
    await rig.service.deliverLocal(message, dismissAfter: nil)
    #expect(await rig.waitForPosts(1))
    await rig.service.shutdown()
  }

  @Test func theManualOverrideHoldsWithModeOffAndEndsOnItsOwn() async throws {
    let (rig, _) = await rig(mode: .off, state: .inactive, presentingFor: 600)
    try await rig.receive("a")
    await rig.settle()
    #expect(await rig.poster.attempts == 0)
    await rig.advance(601)
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    #expect(await rig.poster.summaries.first?.cause == .meeting)
    await rig.service.shutdown()
  }

  @Test func theOverrideEndingDuringARealMeetingKeepsTheHold() async throws {
    let (rig, meeting) = await rig(presentingFor: 600)
    try await rig.receive("a")
    await rig.settle()
    await rig.advance(601)
    #expect(await rig.poster.summaries.isEmpty)
    meeting.set(.inactive)
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    await rig.service.shutdown()
  }

  @Test func aPauseThatOutlastsTheMeetingStillHolds() async throws {
    let (rig, meeting) = await rig()
    let until = rig.clock.now().addingTimeInterval(3600)
    await rig.config.update { $0.pausedUntil = until }
    try await rig.receive("a")
    await rig.settle()
    meeting.set(.inactive)
    await rig.settle()
    #expect(await rig.poster.summaries.isEmpty)
    await rig.advance(3601)
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    await rig.service.shutdown()
  }

  @Test func quietHoursThatOutlastTheMeetingStillHold() async throws {
    let (rig, meeting) = await rig()
    await rig.config.update { $0.quietHours = QuietHours(enabled: true) }
    try await rig.receive("a")
    await rig.settle()
    meeting.set(.inactive)
    await rig.settle()
    #expect(await rig.poster.summaries.isEmpty)
    await rig.advance(rig.untilMorning + 60)
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    await rig.service.shutdown()
  }

  @Test func aMeetingThatStartsAgainBeforeTheSummaryKeepsHolding() async throws {
    let (rig, meeting) = await rig()
    try await rig.receive("a")
    await rig.settle()
    meeting.set(.inactive)
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    meeting.set(zoom)
    try await rig.receive("b")
    await rig.settle()
    #expect(await rig.poster.attempts == 1)
    #expect(await unnotified(rig) == 1)
    await rig.service.shutdown()
  }

  @Test func switchingTheModeOffEndsTheHoldAtTheNextReminderPoll() async throws {
    let (rig, _) = await rig()
    try await rig.receive("a")
    await rig.settle()
    await rig.config.update { $0.meeting.mode = .off }
    await rig.advance(31)
    #expect(await rig.eventually { await rig.poster.summaries.count == 1 })
    await rig.service.shutdown()
  }
}
