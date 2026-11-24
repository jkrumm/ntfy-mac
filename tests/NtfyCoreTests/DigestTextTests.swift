import Foundation
import NtfyCore
import Testing

private let now = Date(timeIntervalSince1970: 1_700_000_000)

private func stored(
  _ topic: String, _ id: String, priority: Int = 3, acknowledged: Bool = false
) -> StoredMessage {
  StoredMessage(
    message: NtfyMessage(
      id: id, topic: topic, time: now, body: "b", priority: Priority(clamping: priority)),
    ackedAt: acknowledged ? now : nil, notifiedAt: now)
}

@Suite struct DigestTextTests {
  @Test func theTopicsAreCountedAndOrderedByCountThenName() {
    let messages =
      (0..<5).map { stored("alerts", "a\($0)") } + (0..<7).map { stored("ci", "c\($0)") }
      + [stored("zeta", "z"), stored("beta", "b")]
    let text = DigestBuilder.deterministicText(for: messages, config: Config())
    #expect(text == "14 messages: ci 7, alerts 5, beta 1, zeta 1")
  }

  @Test func unacknowledgedMessagesAtTheReAlertPriorityAreCounted() {
    let messages = [
      stored("alerts", "1", priority: 5), stored("alerts", "2", priority: 5, acknowledged: true),
      stored("alerts", "3", priority: 5), stored("alerts", "4", priority: 3),
    ]
    let text = DigestBuilder.deterministicText(for: messages, config: Config())
    #expect(text == "4 messages: alerts 4, 2 unacknowledged")
  }

  @Test func theReAlertThresholdSetsWhatCountsAsWaiting() {
    var config = Config()
    config.reAlertMinPriority = 4
    let text = DigestBuilder.deterministicText(
      for: [stored("a", "1", priority: 4), stored("a", "2", priority: 3)], config: config)
    #expect(text == "2 messages: a 2, 1 unacknowledged")
  }

  @Test func oneMessageIsSingular() {
    #expect(
      DigestBuilder.deterministicText(for: [stored("ci", "1")], config: Config())
        == "1 message: ci 1")
  }

  @Test func manyTopicsAreFoldedIntoOne() {
    let messages = (0..<9).map { stored("t\($0)", "m\($0)") }
    let text = DigestBuilder.deterministicText(for: messages, config: Config())
    #expect(text == "9 messages: t0 1, t1 1, t2 1, t3 1, t4 1, t5 1, 3 more topics")
  }

  @Test func theTitleCarriesTheCount() {
    #expect(
      AwayDigest(count: 7, text: "", usedModel: false).title == "While you were away · 7 messages")
    #expect(
      AwayDigest(count: 1, text: "", usedModel: false).title == "While you were away · 1 message")
  }

  @Test func thePromptKeepsTheNewestEntriesAndCutsLongBodies() {
    let long = String(repeating: "x", count: 900)
    let entries = (0..<250).map {
      DigestEntry(
        topic: "t", priority: 3, time: now, title: nil, body: $0 == 0 ? long : "m\($0)",
        acknowledged: true)
    }
    let content = SummaryPrompt.content(for: entries)
    #expect(content.split(separator: "\n").count == 1 + SummaryPrompt.entryLimit)
    #expect(!content.contains(String(repeating: "x", count: 501)))
    #expect(content.contains(String(repeating: "x", count: 500)))
    #expect(content.contains("m199"))
    #expect(!content.contains("m200"))
  }

  @Test func theEntryNamesTopicPriorityAndAcknowledgement() {
    let entry = DigestEntry(
      topic: "ci", priority: 5, time: now, title: "Build failed", body: "main is red")
    let content = SummaryPrompt.content(for: [entry])
    #expect(content.contains("topic=ci priority=5 unacknowledged Build failed: main is red"))
  }
}
