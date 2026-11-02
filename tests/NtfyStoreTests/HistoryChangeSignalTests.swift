import Foundation
import NtfyCore
import Testing

/// What both history stores signal to an in-process observer.
@Suite struct HistoryChangeSignalTests {
  /// One subscriber. A wait that times out cancels the stream, so a listener is not used after
  /// a negative answer.
  private actor Listener {
    private var iterator: AsyncStream<Void>.Iterator

    init(_ store: any AnyHistory) { iterator = store.changes().makeAsyncIterator() }

    func next() async -> Bool {
      var local = iterator
      let element: Void? = await local.next(isolation: self)
      iterator = local
      return element != nil
    }
  }

  /// Whether the listener gets a signal within a short real-time window. A signal already
  /// buffered returns at once; the window is only paid when none is expected.
  private func signalled(_ listener: Listener) async -> Bool {
    let reading = Task { await listener.next() }
    let timer = Task {
      try await Task.sleep(for: .milliseconds(150))
      reading.cancel()
    }
    let answer = await reading.value
    timer.cancel()
    return answer
  }

  @Test(arguments: Backend.allCases)
  func everyKindOfWriteSignals(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1", sequenceID: "seq"))
    let listener = Listener(rig.store)
    let writes: [(String, () async throws -> Void)] = [
      ("append", { try await rig.store.append(rig.message("2")) }),
      ("markNotified", { try await rig.store.markNotified(topic: "alerts", id: "2", at: .now) }),
      ("markRead", { try await rig.store.markRead(topic: "alerts", id: "2") }),
      ("markAllRead", { try await rig.store.markAllRead(topic: "alerts") }),
      ("acknowledge", { try await rig.store.acknowledge(topic: "alerts", id: "2") }),
      ("snooze", { try await rig.store.snooze(topic: "alerts", id: "2", until: .now) }),
      ("clearReminder", { try await rig.store.clearReminder(topic: "alerts", id: "2") }),
      ("markCleared", { try await rig.store.markCleared(topic: "alerts", sequenceID: "seq") }),
      ("withdraw", { try await rig.store.withdraw(topic: "alerts", sequenceID: "seq") }),
      (
        "prune",
        {
          try await rig.store.prune(
            policy: RetentionPolicy(maxPerTopic: 0), now: rig.clock.now())
        }
      ),
    ]
    for (name, write) in writes {
      try await write()
      #expect(await signalled(listener), "\(name) did not signal")
    }
  }

  @Test(arguments: Backend.allCases)
  func aDuplicateAppendAndAnEmptyPruneStayQuiet(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("1"))
    let listener = Listener(rig.store)
    try await rig.store.append(rig.message("1"))
    try await rig.store.prune(policy: RetentionPolicy(), now: rig.clock.now())
    #expect(await signalled(listener) == false)
  }

  @Test(arguments: Backend.allCases)
  func aBurstCoalescesIntoOneSignal(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    let listener = Listener(rig.store)
    for id in ["a", "b", "c"] { try await rig.store.append(rig.message(id)) }
    #expect(await signalled(listener))
    #expect(await signalled(listener) == false)
  }

  @Test(arguments: Backend.allCases)
  func everySubscriberGetsTheSignal(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    let first = Listener(rig.store)
    let second = Listener(rig.store)
    try await rig.store.append(rig.message("1"))
    #expect(await signalled(first))
    #expect(await signalled(second))
  }

  @Test(arguments: Backend.allCases)
  func aNewSubscriberGetsNoReplay(_ backend: Backend) async throws {
    let rig = try HistoryRig(backend)
    try await rig.store.append(rig.message("before"))
    #expect(await signalled(Listener(rig.store)) == false)
  }
}
