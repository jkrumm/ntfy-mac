import Foundation
import Synchronization
import Testing

@testable import NtfyTesting

@Suite struct FakeClockTests {
  private func waitForSleepers(_ clock: FakeClock, count: Int) async {
    while clock.sleeperCount < count { await Task.yield() }
  }

  @Test func advanceMovesNow() {
    let clock = FakeClock(start: Date(timeIntervalSince1970: 100))
    clock.advance(by: .seconds(30))
    #expect(clock.now() == Date(timeIntervalSince1970: 130))
  }

  @Test func sleeperWakesOnlyWhenDeadlinePasses() async {
    let clock = FakeClock()
    let woke = Mutex(false)
    let task = Task {
      try await clock.sleep(for: .seconds(10))
      woke.withLock { $0 = true }
    }
    await waitForSleepers(clock, count: 1)
    clock.advance(by: .seconds(9))
    #expect(clock.sleeperCount == 1)
    #expect(woke.withLock { $0 } == false)
    clock.advance(by: .seconds(1))
    try? await task.value
    #expect(woke.withLock { $0 })
    #expect(clock.sleeperCount == 0)
  }

  @Test func zeroSleepReturnsImmediately() async throws {
    let clock = FakeClock()
    try await clock.sleep(for: .zero)
    #expect(clock.sleeperCount == 0)
  }

  @Test func cancellationUnblocksSleeper() async {
    let clock = FakeClock()
    let task = Task { try await clock.sleep(for: .seconds(60)) }
    await waitForSleepers(clock, count: 1)
    task.cancel()
    let result = await task.result
    #expect(throws: CancellationError.self) { try result.get() }
    #expect(clock.sleeperCount == 0)
  }
}
