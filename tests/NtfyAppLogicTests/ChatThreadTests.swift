import Foundation
import NtfyAppLogic
import NtfyCore
import Testing

@Suite struct ChatGroupingTests {
  private let calendar = HistoryModelRig.utc

  private func message(_ id: String, _ iso: String) -> ChatMessage {
    let time = ISO8601DateFormatter().date(from: iso) ?? .distantPast
    let stored = StoredMessage(
      message: NtfyMessage(id: id, topic: "alerts", time: time, body: id))
    return ChatMessage(detail: MessageDetail(stored, now: time), isOwn: false)
  }

  @Test func daysRunOldestFirstAndSoDoTheirMessages() {
    let days = ChatGrouping.days(
      of: [
        message("c", "2026-03-02T09:00:00Z"), message("a", "2026-03-01T23:59:00Z"),
        message("b", "2026-03-02T00:00:00Z"),
      ], calendar: calendar)
    #expect(days.count == 2)
    #expect(days[0].messages.map(\.id) == ["alerts/a"])
    #expect(days[1].messages.map(\.id) == ["alerts/b", "alerts/c"])
    #expect(days[0].day < days[1].day)
  }

  @Test func messagesAtTheSameInstantKeepAFixedOrder() {
    let forward = ChatGrouping.days(
      of: [message("x", "2026-03-01T10:00:00Z"), message("y", "2026-03-01T10:00:00Z")],
      calendar: calendar)
    let reversed = ChatGrouping.days(
      of: [message("y", "2026-03-01T10:00:00Z"), message("x", "2026-03-01T10:00:00Z")],
      calendar: calendar)
    #expect(forward == reversed)
  }

  @Test func theDayBoundaryFollowsTheCalendarsTimeZone() {
    var berlin = Calendar(identifier: .gregorian)
    berlin.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .gmt
    // 23:30 UTC is already the next day in Berlin (UTC+1 in winter).
    let messages = [message("a", "2026-01-10T22:30:00Z"), message("b", "2026-01-10T23:30:00Z")]
    #expect(ChatGrouping.days(of: messages, calendar: berlin).count == 2)
    #expect(ChatGrouping.days(of: messages, calendar: calendar).count == 1)
    #expect(ChatGrouping.days(of: [], calendar: berlin).isEmpty)
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

@Suite struct ConversationAvatarTests {
  @Test func theFirstKnownEmojiTagWinsOverTheInitial() {
    let avatar = ConversationAvatar(topic: "builds", tags: [["unknown-tag", "warning"], ["tada"]])
    #expect(avatar.isEmoji)
    #expect(avatar.glyph == TagEmoji.emoji(for: "warning"))
  }

  @Test func withoutAnEmojiTheTopicsInitialIsUppercased() {
    let avatar = ConversationAvatar(topic: "builds", tags: [["not-an-emoji"], []])
    #expect(!avatar.isEmoji)
    #expect(avatar.glyph == "B")
  }

  @Test func aTopicWithoutLettersFallsBackToAHash() {
    #expect(ConversationAvatar(topic: "__", tags: []).glyph == "#")
    #expect(ConversationAvatar(topic: "_9x", tags: []).glyph == "9")
  }

  @Test func theColourDependsOnTheNameAlone() {
    let first = ConversationAvatar(topic: "alerts", tags: [])
    let second = ConversationAvatar(topic: "alerts", tags: [["tada"]])
    #expect(first.colorIndex == second.colorIndex)
    // FNV-1a("alerts") % 8, pinned so a change of hash shows up as a changed colour.
    #expect(first.colorIndex == ConversationAvatar.colorIndex(forTopic: "alerts"))
    #expect(ConversationAvatar.colorIndex(forTopic: "alerts") == 6)
    let indexes = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"].map(
      ConversationAvatar.colorIndex(forTopic:))
    #expect(indexes.allSatisfy { (0..<ConversationAvatar.paletteSize).contains($0) })
    #expect(Set(indexes).count > 3)
  }
}

private let calendar = HistoryModelRig.utc
