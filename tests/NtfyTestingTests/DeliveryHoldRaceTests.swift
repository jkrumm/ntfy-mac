import Foundation
import NtfyCore
import NtfyTesting
import Synchronization
import Testing

/// A meeting state whose `current()` suspends until the test opens the gate.
private final class GatedMeeting: MeetingStateProviding {
  private struct State {
    var waiters: [CheckedContinuation<Void, Never>] = []
    var open = false
  }

  private let state = Mutex(State())

  var waiting: Int { state.withLock { $0.waiters.count } }

  func current() async -> MeetingState {
    await withCheckedContinuation { continuation in
      let resume = state.withLock { state -> Bool in
        if state.open { return true }
        state.waiters.append(continuation)
        return false
      }
      if resume { continuation.resume() }
    }
    return .inactive
  }

  func changes() -> AsyncStream<MeetingState> { AsyncStream { $0.finish() } }

  func open() {
    let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
      state.open = true
      defer { state.waiters = [] }
      return state.waiters
    }
    for waiter in waiters { waiter.resume() }
  }
}

@Suite struct DeliveryHoldRaceTests {
  private func gatedRig() async -> (rig: DeliveryRig, gate: GatedMeeting) {
    let gate = GatedMeeting()
    let rig = DeliveryRig(meeting: gate)
    await rig.service.start()
    return (rig, gate)
  }

  private func receiveAndWaitAtTheGate(
    _ rig: DeliveryRig, _ gate: GatedMeeting, sequence: String? = nil
  ) async throws {
    try await rig.receive("a", sequence: sequence)
    #expect(await rig.eventually { gate.waiting >= 1 })
  }

  @Test func aMessageAcknowledgedWhileTheMeetingStateIsReadIsNotPosted() async throws {
    let (rig, gate) = await gatedRig()
    try await receiveAndWaitAtTheGate(rig, gate)
    await rig.service.acknowledge(topic: "t", id: "a")
    gate.open()
    await rig.settle()
    #expect(await rig.poster.posted.isEmpty)
    await rig.service.shutdown()
  }

  @Test func aMessageWithdrawnWhileTheMeetingStateIsReadIsNotPosted() async throws {
    let (rig, gate) = await gatedRig()
    try await receiveAndWaitAtTheGate(rig, gate, sequence: "s")
    await rig.service.withdraw(topic: "t", sequenceID: "s")
    gate.open()
    await rig.settle()
    #expect(await rig.poster.posted.isEmpty)
    await rig.service.shutdown()
  }

  @Test func aMessageSupersededWhileTheMeetingStateIsReadIsNotPosted() async throws {
    let (rig, gate) = await gatedRig()
    try await receiveAndWaitAtTheGate(rig, gate, sequence: "s")
    let newer = rig.message("b", sequence: "s")
    try await rig.history.append(newer)
    await rig.service.deliver(newer)
    gate.open()
    #expect(await rig.waitForPosts(1))
    await rig.settle()
    let ids = await rig.poster.postedIdentifiers
    #expect(ids.count == 1)
    await rig.service.shutdown()
  }

  @Test func withoutAResponseTheMessageIsPostedAfterTheGate() async throws {
    let (rig, gate) = await gatedRig()
    try await receiveAndWaitAtTheGate(rig, gate)
    gate.open()
    #expect(await rig.waitForPosts(1))
    await rig.service.shutdown()
  }
}
