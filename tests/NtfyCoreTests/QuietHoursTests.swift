import Foundation
import Testing

@testable import NtfyCore

@Suite struct QuietHoursTests {
  private func calendar(_ zone: String = "UTC") -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone) ?? .gmt
    return calendar
  }

  private func date(_ iso: String) throws -> Date {
    try Date.ISO8601FormatStyle().parse(iso)
  }

  private func clock(_ text: String) throws -> ClockTime { try #require(ClockTime(text)) }

  private func hours(_ start: String, _ end: String, enabled: Bool = true) throws -> QuietHours {
    QuietHours(enabled: enabled, start: try clock(start), end: try clock(end))
  }

  @Test(arguments: ["00:00", "07:05", "23:59"])
  func clockTimeParsesAndPrintsHHmm(text: String) throws {
    #expect(try clock(text).description == text)
  }

  @Test(arguments: [
    "", "7:00", "24:00", "12:60", "12-30", "12:3", "1200", "ab:cd", "١٢:٣٠", "12:30:00",
  ])
  func clockTimeRejectsAnythingElse(text: String) {
    #expect(ClockTime(text) == nil)
  }

  @Test func aWindowWithinOneDayContainsItsStartButNotItsEnd() throws {
    let day = try hours("09:00", "17:00")
    let utc = calendar()
    #expect(try !day.contains(date("2024-03-05T08:59:59Z"), calendar: utc))
    #expect(try day.contains(date("2024-03-05T09:00:00Z"), calendar: utc))
    #expect(try day.contains(date("2024-03-05T16:59:59Z"), calendar: utc))
    #expect(try !day.contains(date("2024-03-05T17:00:00Z"), calendar: utc))
  }

  @Test func aWindowAcrossMidnightCoversBothSides() throws {
    let night = try hours("22:00", "07:00")
    let utc = calendar()
    #expect(try night.contains(date("2024-03-05T22:00:00Z"), calendar: utc))
    #expect(try night.contains(date("2024-03-05T23:59:00Z"), calendar: utc))
    #expect(try night.contains(date("2024-03-06T00:00:00Z"), calendar: utc))
    #expect(try night.contains(date("2024-03-06T06:59:59Z"), calendar: utc))
    #expect(try !night.contains(date("2024-03-06T07:00:00Z"), calendar: utc))
    #expect(try !night.contains(date("2024-03-06T12:00:00Z"), calendar: utc))
    #expect(try !night.contains(date("2024-03-05T21:59:00Z"), calendar: utc))
  }

  @Test func theCalendarsTimeZoneDecidesTheWallClock() throws {
    let night = try hours("22:00", "07:00")
    let instant = try date("2024-03-05T22:30:00Z")
    #expect(night.contains(instant, calendar: calendar("UTC")))
    #expect(!night.contains(instant, calendar: calendar("Asia/Tokyo")))
    #expect(night.contains(instant, calendar: calendar("America/New_York")) == false)
  }

  @Test func equalStartAndEndIsAnEmptyWindow() throws {
    let empty = try hours("08:00", "08:00")
    let utc = calendar()
    for stamp in ["2024-03-05T07:59:00Z", "2024-03-05T08:00:00Z", "2024-03-05T20:00:00Z"] {
      #expect(try !empty.contains(date(stamp), calendar: utc))
    }
  }

  @Test func aDisabledScheduleContainsNothing() throws {
    let off = try hours("22:00", "07:00", enabled: false)
    #expect(try !off.contains(date("2024-03-05T23:00:00Z"), calendar: calendar()))
  }

  @Test func nextEndIsTheNextMorningFromInsideTheWindow() throws {
    let night = try hours("22:00", "07:00")
    let utc = calendar()
    #expect(
      try night.nextEnd(after: date("2024-03-05T23:00:00Z"), calendar: utc)
        == date("2024-03-06T07:00:00Z"))
    #expect(
      try night.nextEnd(after: date("2024-03-06T03:00:00Z"), calendar: utc)
        == date("2024-03-06T07:00:00Z"))
  }

  @Test func nextEndIsStrictlyAfterTheGivenMoment() throws {
    let night = try hours("22:00", "07:00")
    let end = try date("2024-03-06T07:00:00Z")
    #expect(night.nextEnd(after: end, calendar: calendar()) == end.addingTimeInterval(86_400))
  }

  @Test func theWindowLengthFollowsTheWallClockOnADSTDay() throws {
    let berlin = calendar("Europe/Berlin")
    let night = try hours("22:00", "07:00")
    // Spring forward 2024-03-31 (02:00 -> 03:00): the night lasts 8 real hours.
    let springStart = try date("2024-03-30T21:00:00Z")  // 22:00 CET
    let springEnd = night.nextEnd(after: springStart, calendar: berlin)
    #expect(springEnd == (try date("2024-03-31T05:00:00Z")))  // 07:00 CEST
    #expect(night.contains(springEnd.addingTimeInterval(-1), calendar: berlin))
    #expect(!night.contains(springEnd, calendar: berlin))
    // Fall back 2024-10-27 (03:00 -> 02:00): the night lasts 10 real hours.
    let fallStart = try date("2024-10-26T20:00:00Z")  // 22:00 CEST
    let fallEnd = night.nextEnd(after: fallStart, calendar: berlin)
    #expect(fallEnd == (try date("2024-10-27T06:00:00Z")))  // 07:00 CET
    #expect(night.contains(fallEnd.addingTimeInterval(-1), calendar: berlin))
    #expect(!night.contains(fallEnd, calendar: berlin))
  }

  @Test func anEndInsideTheSpringForwardGapResolvesToTheFirstInstantAfterIt() throws {
    let berlin = calendar("Europe/Berlin")
    let gap = try hours("22:00", "02:30")
    let end = gap.nextEnd(after: try date("2024-03-30T21:30:00Z"), calendar: berlin)
    #expect(end > (try date("2024-03-30T21:30:00Z")))
    #expect(end <= (try date("2024-03-31T01:30:00Z")))
  }
}
