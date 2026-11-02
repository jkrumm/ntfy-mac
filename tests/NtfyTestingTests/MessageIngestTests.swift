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
  let recorder = RecordingDelivery()
  let cursor: InMemoryCursorStore

  init(cursor: String? = nil) {
    self.cursor = InMemoryCursorStore(cursor)
  }

  var ingest: MessageIngest { ingest(delivering: recorder) }

  func ingest(delivering delivery: any Delivering) -> MessageIngest {
    MessageIngest(history: history, delivery: delivery, cursor: cursor)
  }

  /// A real delivery service whose poster always fails.
  func failingService() -> DeliveryService {
    DeliveryService(
      poster: RecordingNotificationPoster(failingWith: .permissionDenied), history: history,
      inbox: history, config: InMemoryConfigStore(), clock: clock)
  }
}

@Suite struct LiveIngestTests {
  @Test func storesDeliversAndThenMovesTheCursor() async throws {
    let parts = Parts()
    try await parts.ingest.ingest(message("1"))
    #expect(await parts.history.recent(limit: 5).map(\.id) == ["1"])
    #expect(await parts.recorder.delivered.map(\.id) == ["1"])
    #expect(await parts.cursor.load() == "1")
  }

  @Test func aDuplicateIsNotDeliveredAgain() async throws {
    let parts = Parts()
    try await parts.ingest.ingest(message("1"))
    try await parts.ingest.ingest(message("1"))
    #expect(await parts.recorder.delivered.count == 1)
  }

  @Test func aStoreFailureThrowsAndLeavesTheCursorAndDeliveryAlone() async throws {
    let parts = Parts(cursor: "old")
    await parts.history.setAppendFailure(.storage("disk full"))
    await #expect(throws: NtfyError.storage("disk full")) {
      try await parts.ingest.ingest(message("1"))
    }
    #expect(await parts.cursor.load() == "old")
    #expect(await parts.recorder.delivered.isEmpty)
  }

  @Test func aFailingPosterDoesNotBlockTheCursor() async throws {
    let parts = Parts()
    let service = parts.failingService()
    try await parts.ingest(delivering: service).ingest(message("1"))
    #expect(await parts.cursor.load() == "1")
    #expect(await parts.history.recent(limit: 5).count == 1)
    await service.shutdown()
  }

  @Test func aCursorFailureIsIgnored() async throws {
    let parts = Parts()
    await parts.cursor.setSaveFailure(.storage("readonly"))
    try await parts.ingest.ingest(message("1"))
    #expect(await parts.recorder.delivered.count == 1)
  }
}

@Suite struct CatchUpIngestTests {
  @Test func theNewMessagesAreStoredAndAnnouncedAsOneBatch() async throws {
    let parts = Parts()
    let batch = [message("1", age: 30 * 60), message("2", age: 10 * 60)]
    let cursor = try await parts.ingest.ingestCatchUp(batch)
    #expect(await parts.recorder.announced.map { $0.map(\.id) } == [["1", "2"]])
    #expect(await parts.recorder.delivered.isEmpty)
    #expect(await parts.history.recent(limit: 5).count == 2)
    #expect(cursor == "2")
    #expect(await parts.cursor.load() == "2")
  }

  @Test func oldMessagesAreStoredAndHandedOverToo() async throws {
    let parts = Parts()
    let batch = (0..<4).map { message("\($0)", topic: "t\($0)", age: 3 * hour - Double($0)) }
    _ = try await parts.ingest.ingestCatchUp(batch)
    #expect(await parts.recorder.announced.map(\.count) == [4])
    #expect(await parts.history.recent(limit: 10).count == 4)
  }

  @Test func messagesAlreadyKnownAreLeftOutOfTheBatch() async throws {
    let parts = Parts()
    let old = message("old", age: 5 * hour)
    try await parts.history.append(old)
    let fresh = message("new", age: 10 * 60)
    _ = try await parts.ingest.ingestCatchUp([old, fresh])
    #expect(await parts.recorder.announced.map { $0.map(\.id) } == [["new"]])
  }

  @Test func aBatchOfOnlyKnownMessagesAnnouncesNothing() async throws {
    let parts = Parts()
    let known = message("1", age: 60)
    try await parts.history.append(known)
    _ = try await parts.ingest.ingestCatchUp([known])
    #expect(await parts.recorder.announced.isEmpty)
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
    #expect(await parts.recorder.announced.isEmpty)
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
    #expect(await parts.recorder.announced.map { $0.map(\.id) } == [["1"]])
    #expect(await parts.history.recent(limit: 5).map(\.id) == ["1"])

    await parts.history.setAppendFailure(nil)
    #expect(try await parts.ingest.ingestCatchUp(batch) == "2")
    #expect(await parts.recorder.announced.map { $0.map(\.id) } == [["1"], ["2"]])
    #expect(await parts.cursor.load() == "2")
  }

  @Test func aFailingPosterStillMovesTheCursor() async throws {
    let parts = Parts()
    let service = parts.failingService()
    let id = try await parts.ingest(delivering: service).ingestCatchUp([message("1", age: 60)])
    #expect(id == "1")
    #expect(await parts.cursor.load() == "1")
    await service.shutdown()
  }
}
