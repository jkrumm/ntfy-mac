import Foundation
import NtfyCore
import Testing

private let start = Date(timeIntervalSince1970: 1_700_000_000)
private let active = SummarySettings(enabled: true, endpoint: "https://x.example.com")

private func later(_ minutes: Double) -> Date { start.addingTimeInterval(minutes * 60) }

@Suite struct ReturnPolicyTests {
  @Test func comingBackAfterTheThresholdIsDueFromTheLastCheck() {
    var policy = ReturnPolicy(now: start)
    #expect(policy.handle(.screensDidSleep, now: later(5), settings: active) == nil)
    #expect(policy.handle(.screensDidWake, now: later(20), settings: active) == start)
  }

  @Test func comingBackBeforeTheThresholdIsNotDue() {
    var policy = ReturnPolicy(now: start)
    _ = policy.handle(.screenLocked, now: later(5), settings: active)
    #expect(policy.handle(.screenUnlocked, now: later(19.9), settings: active) == nil)
  }

  @Test func exactlyTheThresholdCounts() {
    var policy = ReturnPolicy(now: start)
    _ = policy.handle(.willSleep, now: later(1), settings: active)
    #expect(policy.handle(.screensDidWake, now: later(16), settings: active) == start)
  }

  @Test func unlockAndWakeBothEndTheAbsence() {
    var unlock = ReturnPolicy(now: start)
    _ = unlock.handle(.screenLocked, now: later(1), settings: active)
    #expect(unlock.handle(.screenUnlocked, now: later(30), settings: active) == start)
    var wake = ReturnPolicy(now: start)
    _ = wake.handle(.screensDidSleep, now: later(1), settings: active)
    #expect(wake.handle(.screensDidWake, now: later(30), settings: active) == start)
  }

  @Test func aDarkWakeAloneIsNotAReturn() {
    var policy = ReturnPolicy(now: start)
    _ = policy.handle(.willSleep, now: later(1), settings: active)
    #expect(policy.handle(.didWake, now: later(60), settings: active) == nil)
    #expect(policy.handle(.pathChanged(online: true), now: later(61), settings: active) == nil)
  }

  @Test func theFirstLeaveStartsTheAbsence() {
    var policy = ReturnPolicy(now: start)
    _ = policy.handle(.screenLocked, now: later(1), settings: active)
    // The displays going dark after the lock does not restart the clock.
    _ = policy.handle(.screensDidSleep, now: later(12), settings: active)
    #expect(policy.handle(.screensDidWake, now: later(17), settings: active) == start)
  }

  @Test func oneAbsenceYieldsOneDigest() {
    var policy = ReturnPolicy(now: start)
    _ = policy.handle(.screensDidSleep, now: later(1), settings: active)
    #expect(policy.handle(.screensDidWake, now: later(30), settings: active) == start)
    #expect(policy.handle(.screenUnlocked, now: later(31), settings: active) == nil)
  }

  @Test func aReturnWithoutALeaveIsIgnored() {
    var policy = ReturnPolicy(now: start)
    #expect(policy.handle(.screenUnlocked, now: later(60), settings: active) == nil)
  }

  @Test func theDigestStartsWhereTheLastOneStopped() {
    var policy = ReturnPolicy(now: start)
    policy.markChecked(at: later(10))
    _ = policy.handle(.screenLocked, now: later(11), settings: active)
    #expect(policy.handle(.screenUnlocked, now: later(40), settings: active) == later(10))
  }

  @Test func openingTheWindowAfterAWhileIsDueAndCountsAsACheck() {
    var policy = ReturnPolicy(now: start)
    #expect(policy.windowOpened(now: later(20), settings: active) == start)
    #expect(policy.windowOpened(now: later(21), settings: active) == nil)
    #expect(policy.windowOpened(now: later(36), settings: active) == later(21))
  }

  @Test func openingTheWindowSoonAfterANeighbouringCheckIsNotDue() {
    var policy = ReturnPolicy(now: start)
    #expect(policy.windowOpened(now: later(5), settings: active) == nil)
    #expect(policy.windowOpened(now: later(19), settings: active) == nil)
  }

  @Test func aWindowOpenMovesTheStartOfTheNextDigest() {
    var policy = ReturnPolicy(now: start)
    _ = policy.windowOpened(now: later(5), settings: active)
    _ = policy.handle(.screenLocked, now: later(6), settings: active)
    #expect(policy.handle(.screenUnlocked, now: later(30), settings: active) == later(5))
  }

  @Test func theThresholdComesFromTheCurrentSettings() {
    var policy = ReturnPolicy(now: start)
    var short = active
    short.minAwayMinutes = 2
    _ = policy.handle(.screenLocked, now: later(1), settings: short)
    #expect(policy.handle(.screenUnlocked, now: later(4), settings: short) == start)
  }

  @Test func aDisabledDigestIsNeverDue() {
    var policy = ReturnPolicy(now: start)
    _ = policy.handle(.screenLocked, now: later(1), settings: SummarySettings())
    #expect(policy.handle(.screenUnlocked, now: later(90), settings: SummarySettings()) == nil)
    #expect(policy.windowOpened(now: later(180), settings: SummarySettings()) == nil)
  }
}
