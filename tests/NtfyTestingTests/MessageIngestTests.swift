import Foundation
import NtfyCore
import NtfyTesting
import Testing

private let clock = FakeClock()
private let hour: TimeInterval = 3600

private func message(_ id: String, topic: String = "t", age: TimeInterval = 0) -> NtfyMessage {
  NtfyMessage(id: id, topic: topic, time: clock.now().addingTimeInterval(-age), body: "b")
}

private struct Parts {
  let history = InMemoryHistoryStore()
  let poster: RecordingNotificationPoster
  let cursor: InMemoryCursorStore

  init(poster: RecordingNotificationPoster = RecordingNotificationPoster(), cursor: String? = nil) {
    self.poster = poster
    self.cursor = InMemoryCursorStore(cursor)
  }

  var ingest: MessageIngest {
    MessageIngest(history: history, poster: poster, cursor: cursor, clock: clock)
  }
}

@Suite struct LiveIngestTests {
  @Test func storesPostsAndThenMovesTheCursor() async throws {
    let parts = Parts()
    try await parts.ingest.ingest(message("1"))
    #expect(await parts.history.recent(limit: 5).map(\.id) == ["1"])
    #expect(await parts.poster.posted.map(\.id) == ["1"])
    #expect(await parts.cursor.load() == "1")
  }

  @Test func aDuplicateIsNotPostedAgain() async throws {
    let parts = Parts()
    try await parts.ingest.ingest(message("1"))
    try await parts.ingest.ingest(message("1"))
    #expect(await parts.poster.posted.count == 1)
  }

  @Test func aStoreFailureThrowsAndLeavesTheCursorAndThePosterAlone() async throws {
    let parts = Parts(cursor: "old")
    await parts.history.setAppendFailure(.storage("disk full"))
    await #expect(throws: NtfyError.storage("disk full")) {
      try await parts.ingest.ingest(message("1"))
    }
    #expect(await parts.cursor.load() == "old")
    #expect(await parts.poster.posted.isEmpty)
  }

  @Test func aPosterFailureDoesNotBlockTheCursor() async throws {
    let parts = Parts(poster: RecordingNotificationPoster(failingWith: .permissionDenied))
    try await parts.ingest.ingest(message("1"))
    #expect(await parts.cursor.load() == "1")
    #expect(await parts.history.recent(limit: 5).count == 1)
  }

  @Test func aCursorFailureIsIgnored() async throws {
    let parts = Parts()
    await parts.cursor.setSaveFailure(.storage("readonly"))
    try await parts.ingest.ingest(message("1"))
    #expect(await parts.poster.posted.count == 1)
  }
}

@Suite struct CatchUpIngestTests {
  @Test func recentMessagesAreStoredAndPostedIndividually() async throws {
    let parts = Parts()
    let batch = [message("1", age: 30 * 60), message("2", age: 10 * 60)]
    let cursor = try await parts.ingest.ingestCatchUp(batch)
    #expect(await parts.poster.posted.map(\.id) == ["1", "2"])
    #expect(await parts.history.recent(limit: 5).count == 2)
    #expect(cursor == "2")
    #expect(await parts.cursor.load() == "2")
  }

  @Test func olderMessagesCollapseIntoOneSummaryButAreAllStored() async throws {
    let parts = Parts()
    let batch = (0..<4).map { message("\($0)", topic: "t\($0)", age: 3 * hour - Double($0)) }
    _ = try await parts.ingest.ingestCatchUp(batch)
    #expect(await parts.poster.posted.isEmpty)
    #expect(await parts.poster.summaries == [.init(count: 4, oldestTopic: "t0")])
    #expect(await parts.history.recent(limit: 10).count == 4)
  }

  @Test func ancientMessagesAreStoredSilently() async throws {
    let parts = Parts()
    _ = try await parts.ingest.ingestCatchUp([message("1", age: 13 * hour)])
    #expect(await parts.poster.posted.isEmpty)
    #expect(await parts.poster.summaries.isEmpty)
    #expect(await parts.history.recent(limit: 10).count == 1)
    #expect(await parts.cursor.load() == "1")
  }

  @Test func messagesAlreadyKnownDoNotCountTowardsThePolicy() async throws {
    let parts = Parts()
    let old = message("old", age: 5 * hour)
    try await parts.history.append(old)
    let fresh = message("new", age: 10 * 60)
    _ = try await parts.ingest.ingestCatchUp([old, fresh])
    #expect(await parts.poster.posted.map(\.id) == ["new"])
    #expect(await parts.poster.summaries.isEmpty)
  }

  @Test func theCursorIsTheNewestMessageOfTheBatch() async throws {
    let parts = Parts()
    let batch = [message("b", age: 20 * 60), message("c", age: 5 * 60), message("a", age: 40 * 60)]
    #expect(try await parts.ingest.ingestCatchUp(batch) == "c")
  }

  @Test func anEmptyBatchChangesNothing() async throws {
    let parts = Parts(cursor: "keep")
    #expect(try await parts.ingest.ingestCatchUp([]) == nil)
    #expect(await parts.cursor.load() == "keep")
  }

  @Test func aStoreFailureKeepsTheCursorAnnouncesWhatWasStoredAndDoesNotRepeatItOnRetry()
    async throws
  {
    let parts = Parts(cursor: "old")
    let batch = [message("1", age: 60), message("2", age: 30)]
    await parts.history.setAppendFailure(.storage("io"), afterSuccesses: 1)
    await #expect(throws: NtfyError.storage("io")) {
      try await parts.ingest.ingestCatchUp(batch)
    }
    #expect(await parts.cursor.load() == "old")
    #expect(await parts.poster.posted.map(\.id) == ["1"])
    #expect(await parts.history.recent(limit: 5).map(\.id) == ["1"])

    await parts.history.setAppendFailure(nil)
    #expect(try await parts.ingest.ingestCatchUp(batch) == "2")
    #expect(await parts.poster.posted.map(\.id) == ["1", "2"])
    #expect(await parts.cursor.load() == "2")
  }

  @Test func aPosterFailureStillMovesTheCursor() async throws {
    let parts = Parts(poster: RecordingNotificationPoster(failingWith: .permissionDenied))
    #expect(try await parts.ingest.ingestCatchUp([message("1", age: 60)]) == "1")
    #expect(await parts.cursor.load() == "1")
  }
}
