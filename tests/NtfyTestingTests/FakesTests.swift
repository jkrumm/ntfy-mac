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

  @Test func historyReturnsNewestFirstAndTracksCursor() async {
    let store = InMemoryHistoryStore()
    for id in ["1", "2", "3"] { await store.append(message(id)) }
    #expect(await store.recent(limit: 2).map(\.id) == ["3", "2"])
    #expect(await store.lastMessageID() == "3")
  }

  @Test func configStoreRoundTrips() async {
    let store = InMemoryConfigStore()
    await store.save(Config(url: nil, topics: ["a"]))
    #expect(await store.load().topics == ["a"])
  }

  @Test func posterRecordsOrFails() async throws {
    let recorder = RecordingNotificationPoster()
    try await recorder.post(message("1"))
    #expect(await recorder.posted.map(\.id) == ["1"])
    let failing = RecordingNotificationPoster(failingWith: .permissionDenied)
    await #expect(throws: NtfyError.permissionDenied) { try await failing.post(message("2")) }
  }

  @Test func scriptedStreamReplaysThenFails() async {
    let stream = ScriptedMessageStream([.message(message("1")), .fail(.serverUnreachable)])
    var seen: [String] = []
    do {
      for try await item in stream.messages(topics: ["t"], since: nil) { seen.append(item.id) }
      Issue.record("expected failure")
    } catch {
      #expect(error as? NtfyError == .serverUnreachable)
    }
    #expect(seen == ["1"])
  }
}
