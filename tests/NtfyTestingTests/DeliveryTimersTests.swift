import NtfyTesting
import Testing

@testable import NtfyCore

private actor Fired {
  private(set) var generations: [Int] = []
  func add(_ generation: Int) { generations.append(generation) }
}

@Suite struct DeliveryTimersTests {
  private let clock = FakeClock()
  private let fired = Fired()
  private let ref = MessageRef(topic: "t", id: "a")

  private func schedule(
    _ timers: inout DeliveryTimers, _ key: DeliveryTimers.Key, ref: MessageRef? = nil
  ) {
    let fired = fired
    timers.schedule(key, ref: ref ?? self.ref, after: .seconds(10), clock: clock) {
      await fired.add($0)
    }
  }

  private func waitForSleepers(_ count: Int) async {
    for _ in 0..<100_000 where clock.sleeperCount != count { await Task.yield() }
  }

  private let dismiss = DeliveryTimers.Key(kind: .dismiss, identifier: "t/a")
  private let realert = DeliveryTimers.Key(kind: .realert, identifier: "t/a")

  @Test func rescheduleInvalidatesTheEarlierGeneration() async {
    var timers = DeliveryTimers()
    schedule(&timers, dismiss)
    schedule(&timers, dismiss)
    #expect(timers.isCurrent(dismiss, generation: 2))
    #expect(!timers.isCurrent(dismiss, generation: 1))
    let staleFinished = timers.finish(dismiss, generation: 1)
    #expect(!staleFinished)
    #expect(timers.has(dismiss))
    let currentFinished = timers.finish(dismiss, generation: 2)
    #expect(currentFinished)
    #expect(!timers.has(dismiss))
    let repeatFinished = timers.finish(dismiss, generation: 2)
    #expect(!repeatFinished)
    for task in timers.cancelAll() { await task.value }
  }

  @Test func theCurrentTimerFiresWithItsGeneration() async {
    var timers = DeliveryTimers()
    schedule(&timers, dismiss)
    await waitForSleepers(1)
    clock.advance(by: .seconds(10))
    for _ in 0..<1000 where await fired.generations.isEmpty { await Task.yield() }
    #expect(await fired.generations == [1])
  }

  @Test func cancelByRefOnlyStopsThatMessagesTimers() async {
    var timers = DeliveryTimers()
    let other = MessageRef(topic: "t", id: "b")
    let otherKey = DeliveryTimers.Key(kind: .dismiss, identifier: "t/b")
    schedule(&timers, dismiss)
    schedule(&timers, realert)
    schedule(&timers, otherKey, ref: other)
    timers.cancel(ref: ref)
    #expect(!timers.has(dismiss))
    #expect(!timers.has(realert))
    #expect(timers.has(otherKey))
    #expect(timers.identifier(for: other) == "t/b")
    #expect(timers.identifier(for: ref) == nil)
    for task in timers.cancelAll() { await task.value }
  }

  @Test func cancelByIdentifierStopsBothKinds() async {
    var timers = DeliveryTimers()
    schedule(&timers, dismiss)
    schedule(&timers, realert)
    timers.cancel(identifier: "t/a")
    #expect(timers.isEmpty)
  }

  @Test func aCancelledTimerNeverFires() async {
    var timers = DeliveryTimers()
    schedule(&timers, dismiss)
    await waitForSleepers(1)
    timers.cancel(ref: ref)
    await waitForSleepers(0)
    clock.advance(by: .seconds(60))
    for _ in 0..<1000 { await Task.yield() }
    #expect(await fired.generations.isEmpty)
  }

  @Test func cancelAllEmptiesTheSetAndHandsBackTheTasks() async {
    var timers = DeliveryTimers()
    schedule(&timers, dismiss)
    schedule(&timers, realert)
    let tasks = timers.cancelAll()
    #expect(tasks.count == 2)
    #expect(timers.isEmpty)
    for task in tasks { await task.value }
    #expect(clock.sleeperCount == 0)
    #expect(await fired.generations.isEmpty)
  }
}
