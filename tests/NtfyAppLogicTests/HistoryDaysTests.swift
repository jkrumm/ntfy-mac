import Foundation
import NtfyAppLogic
import NtfyCore
import Testing

@Suite struct HistoryGroupingTests {
  private let calendar = HistoryModelRig.utc

  private func message(_ id: String, _ iso: String) -> MessageRow {
    let time = ISO8601DateFormatter().date(from: iso) ?? .distantPast
    return MessageRow(
      StoredMessage(message: NtfyMessage(id: id, topic: "alerts", time: time, body: id)))
  }

  @Test func daysRunNewestFirstAndSoDoTheirMessages() {
    let days = HistoryGrouping.days(
      of: [
        message("c", "2026-03-02T09:00:00Z"), message("a", "2026-03-01T23:59:00Z"),
        message("b", "2026-03-02T00:00:00Z"),
      ], calendar: calendar)
    #expect(days.count == 2)
    #expect(days[0].rows.map(\.id) == ["alerts/c", "alerts/b"])
    #expect(days[1].rows.map(\.id) == ["alerts/a"])
    #expect(days[0].day > days[1].day)
  }

  @Test func messagesAtTheSameInstantKeepAFixedOrder() {
    let forward = HistoryGrouping.days(
      of: [message("x", "2026-03-01T10:00:00Z"), message("y", "2026-03-01T10:00:00Z")],
      calendar: calendar)
    let reversed = HistoryGrouping.days(
      of: [message("y", "2026-03-01T10:00:00Z"), message("x", "2026-03-01T10:00:00Z")],
      calendar: calendar)
    #expect(forward == reversed)
  }

  @Test func theDayBoundaryFollowsTheCalendarsTimeZone() {
    var berlin = Calendar(identifier: .gregorian)
    berlin.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    // 23:30 UTC is already the next day in Berlin (UTC+1 in winter).
    let messages = [message("a", "2026-01-10T22:30:00Z"), message("b", "2026-01-10T23:30:00Z")]
    #expect(HistoryGrouping.days(of: messages, calendar: berlin).count == 2)
    #expect(HistoryGrouping.days(of: messages, calendar: calendar).count == 1)
    #expect(HistoryGrouping.days(of: [], calendar: berlin).isEmpty)
  }

  @Test func theLabelSaysTodayYesterdayOrTheDate() throws {
    let now = try #require(ISO8601DateFormatter().date(from: "2026-03-10T15:00:00Z"))
    func label(_ iso: String) throws -> DayLabel {
      let time = try #require(ISO8601DateFormatter().date(from: iso))
      return DayLabel(day: calendar.startOfDay(for: time), now: now, calendar: calendar)
    }
    #expect(try label("2026-03-10T01:00:00Z") == .today)
    #expect(try label("2026-03-09T23:00:00Z") == .yesterday)
    guard case .date(_, let sameYear) = try label("2026-02-01T00:00:00Z") else {
      Issue.record("expected a date")
      return
    }
    #expect(!sameYear)
    guard case .date(_, let otherYear) = try label("2025-12-31T00:00:00Z") else {
      Issue.record("expected a date")
      return
    }
    #expect(otherYear)
  }
}
