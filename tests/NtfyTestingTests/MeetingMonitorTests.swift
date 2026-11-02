import Foundation
import NtfyCore
import NtfyTesting
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
}
