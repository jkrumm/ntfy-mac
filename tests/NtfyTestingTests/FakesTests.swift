import Foundation
import NtfyCore
import Testing

@testable import NtfyTesting

private func message(_ id: String) -> NtfyMessage {
  NtfyMessage(id: id, topic: "t", time: Date(timeIntervalSince1970: 1), body: "b")
}

@Suite struct FakesTests {
  @Test func secretStoreRoundTrips() async {
    let store = InMemorySecretStore()
    #expect(await store.token() == nil)
    await store.setToken("tk")
    #expect(await store.token() == "tk")
    await store.deleteToken()
    #expect(await store.token() == nil)
  }

  @Test func historyReturnsNewestFirstAndTracksCursor() async throws {
    let store = InMemoryHistoryStore()
    for id in ["1", "2", "3"] { try await store.append(message(id)) }
    #expect(await store.recent(limit: 2).map(\.id) == ["3", "2"])
    #expect(await store.lastMessageID() == "3")
  }

  @Test func configStoreRoundTrips() async {
    let store = InMemoryConfigStore()
    await store.save(Config(url: "https://ntfy.example.com", extraTopics: ["a"]))
    #expect(await store.load().extraTopics == ["a"])
  }

  @Test func posterRecordsOrFails() async throws {
    let recorder = RecordingNotificationPoster()
    try await recorder.post(message("1"))
    #expect(await recorder.posted.map(\.id) == ["1"])
    let failing = RecordingNotificationPoster(failingWith: .permissionDenied)
    await #expect(throws: NtfyError.permissionDenied) { try await failing.post(message("2")) }
  }

  @Test func historyDedupsByTopicAndID() async throws {
    let store = InMemoryHistoryStore()
    #expect(try await store.append(message("1")))
    #expect(try await store.append(message("1")) == false)
    let other = NtfyMessage(id: "1", topic: "u", time: Date(timeIntervalSince1970: 1), body: "b")
    #expect(try await store.append(other))
    #expect(await store.recent(limit: 10).count == 2)
  }

  @Test func posterRecordsSummaries() async throws {
    let recorder = RecordingNotificationPoster()
    try await recorder.postMissedSummary(count: 3, oldestTopic: "t")
    #expect(await recorder.summaries == [.init(count: 3, oldestTopic: "t")])
    let failing = RecordingNotificationPoster(failingWith: .permissionDenied)
    await #expect(throws: NtfyError.permissionDenied) {
      try await failing.postMissedSummary(count: 1, oldestTopic: "t")
    }
  }

  @Test func cursorStoreRoundTrips() async throws {
    let store = InMemoryCursorStore()
    #expect(await store.load() == nil)
    try await store.save("9")
    #expect(await store.load() == "9")
  }

  @Test func scriptedPollerAnswersInOrderAndRecordsCalls() async throws {
    let poller = ScriptedMessagePoller([.messages([message("1")]), .fail(.serverUnreachable)])
    #expect(try await poller.poll(topics: ["t"], since: "0").map(\.id) == ["1"])
    await #expect(throws: NtfyError.serverUnreachable) {
      try await poller.poll(topics: ["t"], since: "1")
    }
    #expect(try await poller.poll(topics: ["t"], since: "1").isEmpty)
    #expect(await poller.calls.map(\.since) == ["0", "1", "1"])
  }

  @Test func scriptedTopicSourceReportsOrFails() async throws {
    #expect(try await ScriptedTopicSource(topics: ["a"]).subscribedTopics() == ["a"])
    let failing = ScriptedTopicSource(failingWith: .unauthorized)
    await #expect(throws: NtfyError.unauthorized) { try await failing.subscribedTopics() }
  }

  @Test func manualSystemEventsReachEverySubscriber() async {
    let source = ManualSystemEvents()
    var first = source.events().makeAsyncIterator()
    var second = source.events().makeAsyncIterator()
    source.send(.didWake)
    source.send(.pathChanged(online: false))
    #expect(await first.next() == .didWake)
    #expect(await first.next() == .pathChanged(online: false))
    #expect(await second.next() == .didWake)
  }

  @Test func scriptedStreamReplaysThenFails() async {
    let stream = ScriptedMessageStream([.message(message("1")), .fail(.serverUnreachable)])
    var seen: [String] = []
    do {
      for try await event in stream.events(topics: ["t"], since: nil) {
        if case .message(let item) = event { seen.append(item.id) }
      }
      Issue.record("expected failure")
    } catch {
      #expect(error as? NtfyError == .serverUnreachable)
    }
    #expect(seen == ["1"])
  }

  @Test func scriptedStreamServesOneScriptPerConnectionAndRecordsCalls() async throws {
    let stream = ScriptedMessageStream(connections: [
      [.event(.open), .message(message("1"))],
      [.message(message("2")), .hold],
    ])
    var first: [StreamEvent] = []
    for try await event in stream.events(topics: ["a"], since: nil) { first.append(event) }
    #expect(first == [.open, .message(message("1"))])

    var second = stream.events(topics: ["a", "b"], since: "1").makeAsyncIterator()
    #expect(try await second.next() == .message(message("2")))

    let held = Task { try await stream.events(topics: ["a"], since: "2").first { _ in true } }
    for _ in 0..<1000 where stream.calls.count < 3 { await Task.yield() }
    held.cancel()
    #expect(try await held.value == nil)
    #expect(
      stream.calls == [
        .init(topics: ["a"], since: nil), .init(topics: ["a", "b"], since: "1"),
        .init(topics: ["a"], since: "2"),
      ])
  }
}
