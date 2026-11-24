import Foundation
import NtfyCore
import Testing

private let now = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14 22:13:20 UTC
private var utc: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
  return calendar
}

private func held(_ config: Config, meeting: MeetingState = .inactive, known: Bool = true) -> Bool {
  DigestHold.holds(config, meeting: meeting, meetingKnown: known, now: now, calendar: utc)
}

@Suite struct DigestHoldTests {
  @Test func nothingHoldsByDefault() {
    #expect(!held(Config()))
  }

  @Test func aPauseInTheFutureHoldsAndAnEndedOneDoesNot() {
    #expect(held(Config(pausedUntil: now.addingTimeInterval(60))))
    #expect(!held(Config(pausedUntil: now.addingTimeInterval(-60))))
  }

  @Test func quietHoursHoldEvenForUrgentBypass() throws {
    let start = try #require(ClockTime(hour: 22, minute: 0))
    let end = try #require(ClockTime(hour: 7, minute: 0))
    let quiet = QuietHours(enabled: true, start: start, end: end, urgentBypass: true)
    #expect(held(Config(quietHours: quiet)))
    #expect(!held(Config(quietHours: QuietHours(enabled: false, start: start, end: end))))
  }

  @Test func aDetectedMeetingHoldsOnlyWithTheModeOn() {
    let meeting = MeetingState.active(.presenting)
    #expect(!held(Config(), meeting: meeting))
    #expect(held(Config(meeting: MeetingSettings(mode: .pause)), meeting: meeting))
  }

  @Test func thePresentingOverrideHoldsWithTheModeOff() {
    let config = Config(meeting: MeetingSettings(presentingUntil: now.addingTimeInterval(600)))
    #expect(held(config))
  }

  @Test func withTheModeOnNoReadingYetHolds() {
    #expect(held(Config(meeting: MeetingSettings(mode: .pause)), known: false))
    #expect(!held(Config(), known: false))
  }
}
