import Foundation
import NtfyCore
import NtfyTesting
import Synchronization
import Testing

@testable import NtfyMacCLI

@Suite struct HistoryFollowerTests {
  private let clock = FakeClock()
  private let store: InMemoryHistoryStore

  init() { store = InMemoryHistoryStore(clock: clock) }

  private func feed(absent: Bool = false) -> HistoryFeed {
    let store = store
    return HistoryFeed { absent ? nil : store }
  }

  private func follower(
    topic: String? = nil, seed: [StoredMessage] = [], absent: Bool = false
  ) -> HistoryFollower {
    HistoryFollower(
      feed: feed(absent: absent), filter: HistoryQuery(topic: topic), clock: clock,
      start: clock.now(), seed: seed)
  }

  private func add(_ id: String, topic: String = "t", age: TimeInterval = 0) async {
    let time = clock.now().addingTimeInterval(-age)
    _ = try? await store.append(NtfyMessage(id: id, topic: topic, time: time, body: id))
  }

  @Test func pollReportsOnlyNewRowsOldestFirstAndOnlyOnce() async throws {
    let follower = follower()
    #expect(try await follower.poll().isEmpty)
    await add("m1", age: 2)
    await add("m2", age: 1)
    #expect(try await follower.poll().map(\.message.id) == ["m1", "m2"])
    #expect(try await follower.poll().isEmpty)
    clock.advance(by: .seconds(5))
    await add("m3")
    #expect(try await follower.poll().map(\.message.id) == ["m3"])
  }

  @Test func seededAndPreExistingRowsAreNotNew() async throws {
    await add("old", age: 10)
    let existing = await store.entries(HistoryQuery())
    let seeded = follower(seed: existing)
    #expect(try await seeded.poll().isEmpty)
    await add("fresh")
    #expect(try await seeded.poll().map(\.message.id) == ["fresh"])
  }

  @Test func theTopicFilterApplies() async throws {
    let follower = follower(topic: "a")
    await add("x", topic: "b")
    await add("y", topic: "a")
    #expect(try await follower.poll().map(\.message.id) == ["y"])
  }

  @Test func aMissingDatabaseIsQuietUntilItAppears() async throws {
    let box = Mutex(false)
    let store = store
    let late = HistoryFeed { box.withLock { $0 } ? store : nil }
    let follower = HistoryFollower(
      feed: late, filter: HistoryQuery(), clock: clock, start: clock.now())
    #expect(try await follower.poll().isEmpty)
    box.withLock { $0 = true }
    await add("m1")
    #expect(try await follower.poll().map(\.message.id) == ["m1"])
  }

  @Test func followHandsOverRowsAsTheClockTicksAndStopsWhenCancelled() async throws {
    let follower = follower()
    let received = Mutex<[String]>([])
    let task = Task {
      try await follower.follow { entry in received.withLock { $0.append(entry.message.id) } }
    }
    await waitForSleeper()
    await add("m1")
    clock.advance(by: .milliseconds(500))
    try await eventually { received.withLock { $0 } == ["m1"] }
    await waitForSleeper()
    await add("m2")
    clock.advance(by: .milliseconds(500))
    try await eventually { received.withLock { $0 } == ["m1", "m2"] }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
  }

  @Test func firstMatchTimesOutAtTheDeadlineAndReturnsAMatch() async throws {
    let follower = follower()
    let deadline = clock.now().addingTimeInterval(2)
    let none = Task { try await follower.firstMatch(until: deadline) { _ in false } }
    for _ in 0..<5 {
      await waitForSleeper(or: none)
      clock.advance(by: .milliseconds(500))
    }
    #expect(try await none.value == nil)

    let later = self.follower()
    let found = Task {
      try await later.firstMatch(until: clock.now().addingTimeInterval(60)) {
        $0.message.id == "hit"
      }
    }
    await waitForSleeper(or: found)
    await add("miss")
    await add("hit")
    clock.advance(by: .milliseconds(500))
    #expect(try await found.value?.message.id == "hit")
  }

  @Test func rowsOlderThanTheWindowAreForgottenButNeverReportedTwice() async throws {
    let follower = follower()
    await add("m1")
    #expect(try await follower.poll().count == 1)
    clock.advance(by: .seconds(600))
    await add("m2")
    #expect(try await follower.poll().map(\.message.id) == ["m2"])
    #expect(try await follower.poll().isEmpty)
  }

  @Test func aBurstLargerThanOnePageLosesNothing() async throws {
    let follower = follower()
    let count = HistoryFollower.pageSize * 2 + 37
    for index in 0..<count { await add("m\(index)", age: Double(count - index) / 100) }
    let fresh = try await follower.poll()
    #expect(fresh.count == count)
    #expect(fresh.first?.message.id == "m0")
    #expect(fresh.last?.message.id == "m\(count - 1)")
    #expect(try await follower.poll().isEmpty)
  }

  @Test func aRowStoredLateInsideTheWindowIsReportedOneOutsideIsNot() async throws {
    let follower = follower()
    await add("m1")
    #expect(try await follower.poll().count == 1)
    await add("late", age: HistoryFollower.window / 2)
    #expect(try await follower.poll().map(\.message.id) == ["late"])
    await add("too-late", age: HistoryFollower.window * 2)
    #expect(try await follower.poll().isEmpty)
  }

  @Test func theSeenMapIsPrunedToTheWindow() async throws {
    let follower = follower()
    await add("m1")
    _ = try await follower.poll()
    clock.advance(by: .seconds(HistoryFollower.window * 3))
    await add("m2")
    _ = try await follower.poll()
    #expect(await follower.seenCount == 1)
  }

  // MARK: Helpers

  private func waitForSleeper() async {
    for _ in 0..<2000 where clock.sleeperCount == 0 {
      try? await Task.sleep(for: .milliseconds(1))
    }
  }

  private func waitForSleeper<T: Sendable>(or task: Task<T, any Error>) async {
    for _ in 0..<2000 where clock.sleeperCount == 0 {
      try? await Task.sleep(for: .milliseconds(1))
    }
  }

  private func eventually(_ condition: () -> Bool) async throws {
    for _ in 0..<2000 where !condition() {
      try await Task.sleep(for: .milliseconds(1))
    }
    #expect(condition())
  }
}
