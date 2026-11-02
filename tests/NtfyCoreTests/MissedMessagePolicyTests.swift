import Foundation
import NtfyCore
import Testing

private let now = Date(timeIntervalSince1970: 1_700_000_000)
private let minute: TimeInterval = 60
private let hour: TimeInterval = 3600

private func message(age: TimeInterval, topic: String = "test", id: String = "m") -> NtfyMessage {
  NtfyMessage(id: id, topic: topic, time: now.addingTimeInterval(-age), body: "hello")
}

@Suite struct MissedMessagePolicyTests {
  @Test func emptyBatchIsSilent() {
    #expect(MissedMessagePolicy.decide([], now: now) == .silent)
  }

  @Test func recentMessagesAreIndividual() {
    let messages = [20, 25, 30].map { message(age: TimeInterval($0) * minute, id: "\($0)") }
    #expect(MissedMessagePolicy.decide(messages, now: now) == .individual(messages))
  }

  @Test func eightMessagesThreeHoursOldAreOneSummary() {
    let messages = (0..<8).map {
      message(age: 3 * hour + TimeInterval($0) * minute, topic: "alerts", id: "\($0)")
    }
    #expect(
      MissedMessagePolicy.decide(messages, now: now) == .summary(count: 8, oldestTopic: "alerts"))
  }

  @Test func fifteenHoursOldIsSilent() {
    let messages = (0..<5).map { message(age: 15 * hour + TimeInterval($0) * minute, id: "\($0)") }
    #expect(MissedMessagePolicy.decide(messages, now: now) == .silent)
  }

  @Test func justPastOneHourIsSummaryAndExactlyOneHourStillIndividual() {
    let over = [message(age: hour + 1)]
    #expect(MissedMessagePolicy.decide(over, now: now) == .summary(count: 1, oldestTopic: "test"))
    let exact = [message(age: hour)]
    #expect(MissedMessagePolicy.decide(exact, now: now) == .individual(exact))
  }

  @Test func justPastTwelveHoursIsSilentAndExactlyTwelveHoursStillSummary() {
    #expect(MissedMessagePolicy.decide([message(age: 12 * hour + 1)], now: now) == .silent)
    let exact = [message(age: 12 * hour)]
    #expect(MissedMessagePolicy.decide(exact, now: now) == .summary(count: 1, oldestTopic: "test"))
  }

  @Test func summaryNamesTheTopicOfTheOldestMessage() {
    let messages = [
      message(age: 2 * hour, topic: "recent-topic", id: "a"),
      message(age: 3 * hour, topic: "oldest-topic", id: "b"),
    ]
    #expect(
      MissedMessagePolicy.decide(messages, now: now)
        == .summary(count: 2, oldestTopic: "oldest-topic"))
  }

  @Test func theOldestMessageDecidesEvenWhenOthersAreFresh() {
    let messages = [message(age: 5 * minute, id: "a"), message(age: 13 * hour, id: "b")]
    #expect(MissedMessagePolicy.decide(messages, now: now) == .silent)
  }
}
