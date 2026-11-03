import Foundation
import NtfyCore
import NtfyTesting
import Synchronization
import Testing

@Suite struct MeetingMonitorTests {
  private let clock = FakeClock()
  private let source = ScriptedMeetingSignalSource()
  private let zoom = MeetingSnapshot(
    audio: [
      AudioProcessState(
        pid: 1, bundleID: "us.zoom.xos", isRunningInput: true, isRunningOutput: true)
    ])

  private func monitor() -> MeetingMonitor {
    MeetingMonitor(source: source, clock: clock)
  }

  private func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<200_000 {
      if await condition() { return true }
      await Task.yield()
    }
    return false
  }

  private func settle() async {
    for _ in 0..<3000 { await Task.yield() }
  }

  private func advance(_ seconds: Double) async {
    clock.advance(by: .seconds(seconds))
    await settle()
  }

  /// Passes `seconds` in one-second steps, so a timer armed late still comes due.
  private func pass(_ seconds: Int) async {
    for _ in 0..<seconds { await advance(1) }
  }

  /// Passes one second at a time until `condition` holds, at most `limit` seconds.
  private func pass(upTo limit: Int, until condition: () async -> Bool) async -> Bool {
    for _ in 0..<limit {
      if await condition() { return true }
      await advance(1)
    }
    return await condition()
  }

  /// The debounce has passed and the reading it triggered was taken.
  private func debounced(reads: Int) async {
    await advance(0.5)
    _ = await eventually { source.snapshotCount == reads }
    await settle()
  }

  @Test func startReadsOnceAndReportsNothingForAQuietMachine() async {
    let monitor = monitor()
    await monitor.start()
    #expect(await eventually { source.snapshotCount == 1 })
    #expect(await monitor.current() == .inactive)
    await monitor.stop()
  }

  @Test func aSignalBecomesAMeetingAfterTheDebounceAndTheDwell() async {
    let monitor = monitor()
    await monitor.start()
    #expect(await eventually { source.snapshotCount == 1 })
    source.update(zoom)
    await settle()
    #expect(source.snapshotCount == 1)  // still debouncing
    await debounced(reads: 2)
    #expect(await monitor.current() == .inactive)  // pending
    #expect(await pass(upTo: 10) { await monitor.current() == .active(.app("Zoom")) })
    await monitor.stop()
  }

  @Test func theMeetingEndsAfterTheReleaseLatchWithoutAnotherEvent() async {
    let monitor = monitor()
    await monitor.start()
    #expect(await eventually { source.snapshotCount == 1 })
    source.update(zoom)
    await debounced(reads: 2)
    #expect(await pass(upTo: 10) { await monitor.current().isActive })
    source.set(MeetingSnapshot())
    await pass(40)  // the poll finds the quiet machine; the latch holds
    #expect(await monitor.current().isActive)
    #expect(await pass(upTo: 20) { await monitor.current() == .inactive })
    await monitor.stop()
  }

  @Test func aSubscriberSeesTheCurrentStateAndEveryChange() async {
    let monitor = monitor()
    var iterator = monitor.changes().makeAsyncIterator()
    #expect(await iterator.next() == .inactive)
    await monitor.start()
    #expect(await iterator.next() == .inactive)  // the first reading landed
    #expect(await eventually { source.snapshotCount == 1 })
    source.update(zoom)
    await debounced(reads: 2)
    #expect(await pass(upTo: 10) { await monitor.current().isActive })
    #expect(await iterator.next() == .active(.app("Zoom")))
    await monitor.stop()
    #expect(await iterator.next() == .inactive)
  }

  @Test func nothingIsReadBeforeStartOrAfterStop() async {
    let monitor = monitor()
    await settle()
    #expect(source.snapshotCount == 0)
    await monitor.start()
    #expect(await eventually { source.snapshotCount == 1 })
    await monitor.stop()
    source.update(zoom)
    await advance(60)
    #expect(source.snapshotCount == 1)
    #expect(await monitor.current() == .inactive)
  }

  @Test func startIsIdempotent() async {
    let monitor = monitor()
    await monitor.start()
    await monitor.start()
    #expect(await eventually { source.snapshotCount >= 1 })
    await settle()
    #expect(source.snapshotCount == 1)
    await monitor.stop()
  }

  // MARK: First reading and overlapping lifecycle

  @Test func startReturnsOnceTheFirstReadingExists() async {
    let monitor = monitor()
    #expect(await monitor.hasReading())  // never started: nothing to wait for
    await monitor.start()
    #expect(await monitor.hasReading())
    #expect(source.snapshotCount == 1)
    #expect(clock.sleeperCount <= 1)  // no leftover timeout
    await monitor.stop()
  }

  @Test func startLetsGoAfterTheTimeoutWhenTheFirstReadingIsSlow() async {
    let slow = SlowSource()
    let monitor = MeetingMonitor(source: slow, clock: clock)
    let started = Task { await monitor.start() }
    #expect(await eventually { clock.sleeperCount >= 1 })
    #expect(!(await monitor.hasReading()))
    await advance(3)
    await started.value
    #expect(!(await monitor.hasReading()))
    slow.release()
    #expect(await eventually { await monitor.hasReading() })
    await monitor.stop()
  }

  @Test func aStopWhileStartWaitsEndsTheWaitAndLeavesItStopped() async {
    let slow = SlowSource()
    let monitor = MeetingMonitor(source: slow, clock: clock)
    let started = Task { await monitor.start() }
    #expect(await eventually { clock.sleeperCount >= 1 })
    // The first reading is under way before the stop, so it is exactly one under any scheduling.
    #expect(await eventually { slow.reads >= 1 })
    slow.release()
    await monitor.stop()
    await started.value
    source.update(zoom)
    await advance(60)
    #expect(slow.reads == 1)
    #expect(await monitor.current() == .inactive)
  }

  @Test func aStartDuringAStopKeepsItsOwnState() async {
    let monitor = monitor()
    await monitor.start()
    source.update(zoom)
    await debounced(reads: 2)
    #expect(await pass(upTo: 10) { await monitor.current().isActive })
    // The stop's synchronous part (state reset) has run once `current()` reads inactive; only
    // then does the start overlap the rest of the stop, in a fixed order.
    let stopping = Task { await monitor.stop() }
    #expect(await eventually { await monitor.current() == .inactive })
    await monitor.start()
    await stopping.value
    #expect(await pass(upTo: 10) { await monitor.current().isActive })
    await monitor.stop()
    #expect(await monitor.current() == .inactive)
  }
}

/// A source whose snapshot waits until the test releases it (only the first one).
private final class SlowSource: MeetingSignalSource {
  private let gate = Mutex(State())

  private struct State {
    var waiting: CheckedContinuation<Void, Never>?
    var released = false
    var reads = 0
  }

  var reads: Int { gate.withLock { $0.reads } }

  func release() {
    let waiter = gate.withLock { state -> CheckedContinuation<Void, Never>? in
      state.released = true
      defer { state.waiting = nil }
      return state.waiting
    }
    waiter?.resume()
  }

  func snapshot() async -> MeetingSnapshot {
    gate.withLock { $0.reads += 1 }
    await withCheckedContinuation { continuation in
      let resumeNow = gate.withLock { state -> Bool in
        if state.released { return true }
        state.waiting = continuation
        return false
      }
      if resumeNow { continuation.resume() }
    }
    return MeetingSnapshot()
  }

  func changes() -> AsyncStream<Void> { AsyncStream { _ in } }
}
