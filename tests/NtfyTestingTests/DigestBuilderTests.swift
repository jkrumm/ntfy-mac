import Foundation
import NtfyCore
import NtfyTesting
import Testing

private let now = Date(timeIntervalSince1970: 1_700_000_000)

@Suite struct DigestBuilderTests {
  private func store(_ clock: FakeClock = FakeClock(start: now)) -> InMemoryHistoryStore {
    InMemoryHistoryStore(clock: clock)
  }

  @discardableResult
  private func add(
    _ history: InMemoryHistoryStore, topic: String = "ci", id: String, ageMinutes: Double = 5,
    priority: Int = 3, notified: Bool = true
  ) async -> NtfyMessage {
    let message = NtfyMessage(
      id: id, topic: topic, time: now.addingTimeInterval(-ageMinutes * 60), title: "T\(id)",
      body: "body \(id)", priority: Priority(clamping: priority))
    _ = try? await history.append(message)
    if notified { await history.markNotified(topic: topic, id: id, at: now) }
    return message
  }

  @Test func onlyMessagesThatWereShownAndNotMutedAreCollected() async throws {
    let history = store()
    await add(history, id: "shown")
    await add(history, id: "never-shown", notified: false)
    await add(history, topic: "muted", id: "muted")
    await add(history, topic: "quiet", id: "low", priority: 2)
    await add(history, id: "old", ageMinutes: 600)
    var config = Config()
    config.updateTopic("muted") { $0.mute = true }
    config.updateTopic("quiet") { $0.minPriority = 3 }
    let builder = DigestBuilder(inbox: history)
    let found = try await builder.collect(
      since: now.addingTimeInterval(-3600), config: config)
    #expect(found.map(\.message.id) == ["shown"])
  }

  @Test func aTopicHiddenFromAllStillCounts() async throws {
    let history = store()
    await add(history, topic: "noise", id: "n1")
    var config = Config()
    config.updateTopic("noise") { $0.hideFromAll = true }
    let found = try await DigestBuilder(inbox: history).collect(
      since: now.addingTimeInterval(-3600), config: config)
    #expect(found.map(\.message.id) == ["n1"])
  }

  @Test func theModelWritesTheTextAndSeesTheMessages() async throws {
    let history = store()
    await add(history, id: "1", priority: 5)
    await add(history, topic: "alerts", id: "2")
    let summarizer = ScriptedSummarizer(.success("  Two alerts, one urgent.\n"))
    let builder = DigestBuilder(inbox: history)
    let messages = try await builder.collect(since: now.addingTimeInterval(-3600), config: Config())
    let digest = await builder.digest(of: messages, config: Config(), summarizer: summarizer)
    #expect(digest == AwayDigest(count: 2, text: "Two alerts, one urgent.", usedModel: true))
    let calls = await summarizer.calls
    #expect(calls.count == 1)
    #expect(Set(calls.first?.map(\.topic) ?? []) == ["ci", "alerts"])
    #expect(calls.first?.contains { $0.priority == 5 && !$0.acknowledged } == true)
  }

  @Test(arguments: [
    NtfyError.serverUnreachable, .unauthorized, .rateLimited(retryAfter: nil),
    .invalidResponse("HTTP 400"),
  ]) func aFailingModelFallsBackToTheCounts(error: NtfyError) async throws {
    let history = store()
    await add(history, id: "1")
    await add(history, id: "2")
    let log = LogBox()
    let builder = DigestBuilder(inbox: history, log: { log.add($0) })
    let messages = try await builder.collect(since: now.addingTimeInterval(-3600), config: Config())
    let digest = await builder.digest(
      of: messages, config: Config(), summarizer: ScriptedSummarizer(.failure(error)))
    #expect(digest.text == "2 messages: ci 2")
    #expect(!digest.usedModel)
    #expect(digest.failure != nil)
    #expect(log.lines.count == 1)
  }

  @Test func anEmptyAnswerFallsBackToo() async throws {
    let history = store()
    await add(history, id: "1")
    let builder = DigestBuilder(inbox: history)
    let messages = try await builder.collect(since: now.addingTimeInterval(-3600), config: Config())
    let digest = await builder.digest(
      of: messages, config: Config(), summarizer: ScriptedSummarizer(.success(" \n")))
    #expect(digest.text == "1 message: ci 1")
    #expect(!digest.usedModel)
  }

  @Test func withoutASummarizerTheCountsStandIn() async throws {
    let history = store()
    await add(history, id: "1")
    let builder = DigestBuilder(inbox: history)
    let messages = try await builder.collect(since: now.addingTimeInterval(-3600), config: Config())
    let digest = await builder.digest(of: messages, config: Config(), summarizer: nil)
    #expect(digest == AwayDigest(count: 1, text: "1 message: ci 1", usedModel: false))
  }
}

private final class LogBox: @unchecked Sendable {
  private let lock = NSLock()
  private var stored: [String] = []
  var lines: [String] { lock.withLock { stored } }
  func add(_ line: String) { lock.withLock { stored.append(line) } }
}

/// The digest builds a summarizer only for a configuration that can use one, so a disabled digest
/// or a missing endpoint or key sends nothing anywhere.
@Suite struct SummarizerProviderTests {
  private actor Made {
    var calls: [[String]] = []
    func record(_ call: [String]) { calls.append(call) }
  }

  private func provider(key: String?, made: Made) -> SummarizerProvider {
    SummarizerProvider(
      keys: InMemorySecretStore(token: key),
      make: { endpoint, key, model, insecure in
        Task { await made.record([endpoint, key, model, String(insecure)]) }
        return ScriptedSummarizer()
      })
  }

  private func settle() async {
    for _ in 0..<50 { await Task.yield() }
  }

  @Test func aDisabledDigestBuildsNothing() async {
    let made = Made()
    var config = Config()
    config.summary = SummarySettings(enabled: false, endpoint: "https://x.example.com")
    #expect(await provider(key: "k", made: made).summarizer(for: config) == nil)
    await settle()
    #expect(await made.calls.isEmpty)
  }

  @Test func anEnabledDigestWithoutAnEndpointBuildsNothing() async {
    let made = Made()
    var config = Config()
    config.summary.enabled = true
    #expect(await provider(key: "k", made: made).summarizer(for: config) == nil)
    await settle()
    #expect(await made.calls.isEmpty)
  }

  @Test func withoutAKeyNothingIsBuilt() async {
    let made = Made()
    var config = Config()
    config.summary = SummarySettings(enabled: true, endpoint: "https://x.example.com")
    #expect(await provider(key: nil, made: made).summarizer(for: config) == nil)
    #expect(await provider(key: "", made: made).summarizer(for: config) == nil)
    await settle()
    #expect(await made.calls.isEmpty)
  }

  @Test func aConfiguredDigestGetsItsEndpointKeyAndModel() async {
    let made = Made()
    var config = Config(allowInsecure: true)
    config.summary = SummarySettings(
      enabled: true, endpoint: "https://gw.example.com/anthropic", model: "haiku")
    #expect(await provider(key: "door", made: made).summarizer(for: config) != nil)
    await settle()
    #expect(await made.calls == [["https://gw.example.com/anthropic", "door", "haiku", "true"]])
  }
}
