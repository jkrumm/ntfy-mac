import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

private struct DigestRig {
  let clock = FakeClock()
  let history: InMemoryHistoryStore
  let config: InMemoryConfigStore
  let summarizer: ScriptedSummarizer
  let poster = RecordingNotificationPoster()
  let events = ManualSystemEvents()
  let runner: AwayDigestRunner
  let meeting = ManualMeetingState()

  init(
    summary: SummarySettings = SummarySettings(
      enabled: true, endpoint: "https://gw.example.com/anthropic"),
    key: String? = "door", outcome: Result<String, NtfyError> = .success("Two alerts, one urgent.")
  ) {
    history = InMemoryHistoryStore(clock: clock)
    config = InMemoryConfigStore(Config(summary: summary))
    summarizer = ScriptedSummarizer(outcome)
    let summarizer = summarizer
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    runner = AwayDigestRunner(
      events: events, config: config, inbox: history,
      summarizers: SummarizerProvider(
        keys: InMemorySecretStore(token: key), make: { _, _, _, _ in summarizer }),
      poster: poster, clock: clock, meeting: meeting, calendar: utc)
  }

  /// A message that arrived and was shown now.
  func arrive(_ id: String, topic: String = "ci", priority: Int = 3) async {
    let message = NtfyMessage(
      id: id, topic: topic, time: clock.now(), title: "T\(id)", body: "body",
      priority: Priority(clamping: priority))
    _ = try? await history.append(message)
    await history.markNotified(topic: topic, id: id, at: clock.now())
  }

  func minutes(_ count: Double) { clock.advance(by: .seconds(count * 60)) }

  /// Three messages, then an absence of `away` minutes that ends with `returning`.
  func absence(away: Double, messages: Int = 3, returning: SystemEvent = .screenUnlocked) async {
    minutes(1)
    for index in 0..<messages { await arrive("m\(index)") }
    await runner.process(.screenLocked)
    minutes(away)
    await runner.process(returning)
  }
}

@Suite struct AwayDigestRunnerTests {
  @Test func returningAfterALongAbsencePostsTheModelsDigest() async {
    let rig = DigestRig()
    await rig.absence(away: 20)
    #expect(
      await rig.poster.digests == [
        .init(title: "While you were away · 3 messages", body: "Two alerts, one urgent.")
      ])
    #expect(await rig.summarizer.calls.count == 1)
  }

  @Test(arguments: [SystemEvent.screenUnlocked, .screensDidWake])
  func unlockAndWakeBothCount(event: SystemEvent) async {
    let rig = DigestRig()
    await rig.absence(away: 20, returning: event)
    #expect(await rig.poster.digests.count == 1)
  }

  @Test func aShortAbsenceSaysNothing() async {
    let rig = DigestRig()
    await rig.absence(away: 10)
    #expect(await rig.poster.digests.isEmpty)
    #expect(await rig.summarizer.calls.isEmpty)
  }

  @Test func fewerMessagesThanTheMinimumSayNothingAndCarryOver() async {
    let rig = DigestRig()
    await rig.absence(away: 20, messages: 2)
    #expect(await rig.poster.digests.isEmpty)
    await rig.arrive("late")
    await rig.runner.process(.screenLocked)
    rig.minutes(20)
    await rig.runner.process(.screenUnlocked)
    #expect(await rig.poster.digests.map(\.title) == ["While you were away · 3 messages"])
  }

  @Test func theNextDigestStartsWhereTheLastOneStopped() async {
    let rig = DigestRig()
    await rig.absence(away: 20)
    rig.minutes(1)
    await rig.arrive("n1")
    await rig.arrive("n2")
    await rig.arrive("n3")
    await rig.arrive("n4")
    await rig.runner.process(.screenLocked)
    rig.minutes(20)
    await rig.runner.process(.screenUnlocked)
    let titles = await rig.poster.digests.map(\.title)
    #expect(titles == ["While you were away · 3 messages", "While you were away · 4 messages"])
  }

  @Test func aFailingEndpointPostsTheCountsInstead() async {
    let rig = DigestRig(outcome: .failure(.serverUnreachable))
    await rig.absence(away: 20)
    #expect(
      await rig.poster.digests == [
        .init(title: "While you were away · 3 messages", body: "3 messages: ci 3")
      ])
  }

  @Test func aMissingKeyPostsTheCountsAndAsksNobody() async {
    let rig = DigestRig(key: nil)
    await rig.absence(away: 20)
    #expect(await rig.poster.digests.map(\.body) == ["3 messages: ci 3"])
    #expect(await rig.summarizer.calls.isEmpty)
  }

  @Test func aDisabledDigestPostsNothingAndMakesNoRequest() async {
    let rig = DigestRig(summary: SummarySettings(enabled: false, endpoint: "https://x.example.com"))
    await rig.absence(away: 90)
    await rig.runner.windowOpened()
    #expect(await rig.poster.digests.isEmpty)
    #expect(await rig.summarizer.calls.isEmpty)
  }

  @Test func withoutAnEndpointNothingIsPostedAndNothingIsAsked() async {
    let rig = DigestRig(summary: SummarySettings(enabled: true))
    await rig.absence(away: 90)
    #expect(await rig.poster.digests.isEmpty)
    #expect(await rig.summarizer.calls.isEmpty)
  }

  @Test func openingTheWindowAfterAWhilePostsOnceAndNotAgainRightAway() async {
    let rig = DigestRig()
    rig.minutes(1)
    for index in 0..<3 { await rig.arrive("m\(index)") }
    rig.minutes(20)
    await rig.runner.windowOpened()
    #expect(await rig.poster.digests.count == 1)
    await rig.runner.windowOpened()
    #expect(await rig.poster.digests.count == 1)
  }

  @Test func openingTheWindowSoonAfterLaunchPostsNothing() async {
    let rig = DigestRig()
    rig.minutes(1)
    for index in 0..<3 { await rig.arrive("m\(index)") }
    rig.minutes(5)
    await rig.runner.windowOpened()
    #expect(await rig.poster.digests.isEmpty)
  }

  @Test func aPosterThatFailsLosesTheDigestAndKeepsTheMessagesForTheNextOne() async {
    let rig = DigestRig()
    await rig.poster.failNext(1)
    await rig.absence(away: 20)
    #expect(await rig.poster.digests.isEmpty)
    await rig.runner.process(.screenLocked)
    rig.minutes(20)
    await rig.runner.process(.screenUnlocked)
    #expect(await rig.poster.digests.map(\.title) == ["While you were away · 3 messages"])
  }

  @Test func aPauseHoldsTheDigestAndTheMessagesRollOver() async {
    let rig = DigestRig()
    await rig.config.update { $0.pausedUntil = rig.clock.now().addingTimeInterval(3600) }
    await rig.absence(away: 20)
    #expect(await rig.poster.digests.isEmpty)
    #expect(await rig.summarizer.calls.isEmpty)
    await rig.config.update { $0.pausedUntil = nil }
    await rig.runner.process(.screenLocked)
    rig.minutes(20)
    await rig.runner.process(.screenUnlocked)
    #expect(await rig.poster.digests.map(\.title) == ["While you were away · 3 messages"])
  }

  @Test func quietHoursHoldTheDigest() async throws {
    let rig = DigestRig()
    let start = try #require(ClockTime(hour: 0, minute: 0))
    let end = try #require(ClockTime(hour: 23, minute: 59))
    await rig.config.update { $0.quietHours = QuietHours(enabled: true, start: start, end: end) }
    await rig.absence(away: 20)
    #expect(await rig.poster.digests.isEmpty)
  }

  @Test func aMeetingHoldsTheDigest() async {
    let rig = DigestRig()
    await rig.config.update { $0.meeting.mode = .pause }
    rig.meeting.set(.active(.presenting))
    await rig.absence(away: 20)
    #expect(await rig.poster.digests.isEmpty)
  }

  @Test func theEventStreamDrivesTheRunner() async {
    let rig = DigestRig()
    await rig.runner.start()
    rig.minutes(1)
    for index in 0..<3 { await rig.arrive("m\(index)") }
    rig.events.send(.screenLocked)
    for _ in 0..<2_000 { await Task.yield() }
    rig.minutes(20)
    rig.events.send(.screenUnlocked)
    var posted = false
    for _ in 0..<200_000 where !posted {
      posted = await rig.poster.digests.count == 1
      await Task.yield()
    }
    await rig.runner.stop()
    #expect(posted)
  }
}
