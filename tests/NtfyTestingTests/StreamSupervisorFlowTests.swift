import Foundation
import NtfyCore
import NtfyTesting
import Testing

private let hour: TimeInterval = 3600

@Suite struct SupervisorCatchUpTests {
  @Test func startupReplayOfRecentMessagesIsOneBatch() async {
    let batch = [
      SupervisorRig.message("m1", age: 30 * 60), SupervisorRig.message("m2", age: 10 * 60),
    ]
    let rig = SupervisorRig(cursor: "c0", polls: [.messages(batch)])
    #expect(await rig.connect())
    #expect(await rig.recorder.announced.map { $0.map(\.id) } == [["m1", "m2"]])
    #expect(rig.stream.calls[0].since == "m2")
    let polls = await rig.poller.calls
    #expect(polls.map(\.since) == ["c0"])
    #expect(polls.map(\.topics) == [["alpha"]])
    await rig.supervisor.stop()
  }

  @Test func startupReplayOfOlderMessagesIsOneBatch() async {
    let batch = (0..<3).map { SupervisorRig.message("m\($0)", age: 3 * hour - Double($0)) }
    let rig = SupervisorRig(cursor: "c0", polls: [.messages(batch)])
    #expect(await rig.connect())
    #expect(await rig.recorder.delivered.isEmpty)
    #expect(await rig.recorder.announced.map { $0.map(\.id) } == [["m0", "m1", "m2"]])
    #expect(await rig.history.recent(limit: 10).count == 3)
    await rig.supervisor.stop()
  }

  @Test func startupReplayOfAncientMessagesIsStillHandedToDelivery() async {
    let rig = SupervisorRig(
      cursor: "c0", polls: [.messages([SupervisorRig.message("old", age: 15 * hour)])])
    #expect(await rig.connect())
    #expect(await rig.recorder.delivered.isEmpty)
    #expect(await rig.recorder.announced.map { $0.map(\.id) } == [["old"]])
    #expect(await rig.history.recent(limit: 10).count == 1)
    #expect(await rig.cursor.load() == "old")
    await rig.supervisor.stop()
  }

  @Test func aFailingCatchUpIsAConnectionFailure() async {
    let rig = SupervisorRig(cursor: "c0", polls: [.fail(.unauthorized)])
    await rig.supervisor.start()
    #expect(await rig.waitFor(.halted(.unauthorized)))
    #expect(rig.stream.calls.isEmpty)
    await rig.supervisor.stop()
  }

  @Test func theFirstRunStartsAtTheCurrentTimeAndPersistsIt() async {
    let rig = SupervisorRig()
    #expect(await rig.connect())
    let start = String(Int(rig.clock.now().timeIntervalSince1970))
    #expect(rig.stream.calls[0].since == start)
    #expect(await rig.cursor.load() == start)
    #expect(await rig.poller.calls.isEmpty)
    await rig.supervisor.stop()
  }

  @Test func aPollRequestTriggersACatchUp() async {
    let late = SupervisorRig.message("late", age: 60)
    let polled = SupervisorRig(cursor: "c0", polls: [.messages([]), .messages([late])])
    #expect(await polled.connect())
    polled.stream.send(.pollRequest)
    #expect(
      await polled.eventually {
        await polled.recorder.announced.flatMap { $0 }.map(\.id) == ["late"]
      })
    #expect(await polled.cursor.load() == "late")
    await polled.supervisor.stop()
  }
}

@Suite struct SupervisorIngestTests {
  @Test func liveMessagesAreStoredPostedAndAdvanceTheCursor() async {
    let rig = SupervisorRig(cursor: "c0")
    #expect(await rig.connect())
    rig.stream.send(rig.message("m1"))
    #expect(await rig.eventually { await rig.cursor.load() == "m1" })
    #expect(await rig.recorder.delivered.map(\.id) == ["m1"])
    #expect(await rig.history.recent(limit: 5).map(\.id) == ["m1"])
    await rig.supervisor.stop()
  }

  @Test func duplicatesAreNotPostedAgain() async throws {
    let rig = SupervisorRig(cursor: "c0")
    try await rig.history.append(rig.message("known"))
    #expect(await rig.connect())
    rig.stream.send(rig.message("known"))
    rig.stream.send(rig.message("fresh"))
    rig.stream.send(rig.message("fresh"))
    rig.stream.send(rig.message("last"))
    #expect(await rig.eventually { await rig.cursor.load() == "last" })
    #expect(await rig.recorder.delivered.map(\.id) == ["fresh", "last"])
    await rig.supervisor.stop()
  }

  @Test func aStoreFailureKeepsTheCursorAndTheMessageIsFetchedAgain() async throws {
    let late = SupervisorRig.message("m1")
    let rig = SupervisorRig(cursor: "c0", polls: [.messages([]), .messages([late])])
    #expect(await rig.connect())
    await rig.history.setAppendFailure(.storage("disk full"))
    rig.stream.send(late)
    #expect(await rig.waitForBackoff()?.attempt == 1)
    #expect(await rig.cursor.load() == "c0")
    #expect(await rig.recorder.delivered.isEmpty)

    await rig.history.setAppendFailure(nil)
    #expect(await rig.waitForSleepers(1))
    await rig.advance(5)
    #expect(await rig.waitForCalls(2))
    #expect(
      await rig.eventually { await rig.recorder.announced.flatMap { $0 }.map(\.id) == ["m1"] })
    #expect(await rig.cursor.load() == "m1")
    #expect(rig.stream.calls[1].since == "m1")
    await rig.supervisor.stop()
  }

  @Test func aFailingPosterNeverBlocksTheStream() async {
    let clock = FakeClock()
    let service = DeliveryService(
      poster: RecordingNotificationPoster(failingWith: .permissionDenied),
      history: InMemoryHistoryStore(), inbox: InMemoryHistoryStore(), config: InMemoryConfigStore(),
      clock: clock)
    let rig = SupervisorRig(cursor: "c0", delivery: service)
    #expect(await rig.connect())
    rig.stream.send(rig.message("m1"))
    rig.stream.send(rig.message("m2"))
    #expect(await rig.eventually { await rig.cursor.load() == "m2" })
    #expect(await rig.supervisor.currentStatus == .connected)
    await rig.supervisor.stop()
    await service.shutdown()
  }

  @Test func deleteAndClearEventsReachTheSinkVerbatim() async {
    let rig = SupervisorRig(cursor: "c0")
    #expect(await rig.connect())
    let delete = StreamEvent.messageDelete(topic: "alpha", sequenceID: "s1")
    let clear = StreamEvent.messageClear(topic: "alpha", sequenceID: "s2")
    rig.stream.send(delete)
    rig.stream.send(clear)
    #expect(await rig.eventually { await rig.sink.events.count == 2 })
    #expect(await rig.sink.events == [delete, clear])
    #expect(await rig.recorder.delivered.isEmpty)
    await rig.supervisor.stop()
  }
}

@Suite struct SupervisorLifecycleTests {
  @Test func stopLeavesNothingRunning() async {
    let rig = SupervisorRig(cursor: "c0")
    #expect(await rig.connect())
    await rig.supervisor.stop()
    #expect(await rig.supervisor.currentStatus == .stopped)
    #expect(rig.clock.sleeperCount == 0)
    #expect(await rig.eventually { rig.stream.liveConnectionCount == 0 })

    rig.events.send(.didWake)
    await rig.advance(86_400)
    #expect(rig.stream.calls.count == 1)
  }

  @Test func stopWhileBackingOffAndWhileOfflineLeavesNoTimer() async {
    let rig = SupervisorRig(cursor: "c0")
    await rig.supervisor.start()
    #expect(await rig.waitForCalls(1))
    rig.stream.fail(.serverUnreachable)
    #expect(await rig.waitForBackoff() != nil)
    await rig.supervisor.stop()
    #expect(rig.clock.sleeperCount == 0)
  }

  @Test func theStatusStreamReportsEachChange() async {
    let rig = SupervisorRig(cursor: "c0")
    var statuses = rig.supervisor.status.makeAsyncIterator()
    #expect(await statuses.next() == .stopped)
    await rig.supervisor.start()
    #expect(await statuses.next() == .connecting)
    #expect(await rig.waitForCalls(1))
    rig.stream.send(.open)
    #expect(await statuses.next() == .connected)
    await rig.supervisor.stop()
    #expect(await statuses.next() == .stopped)
  }

  @Test func theActivityHookBracketsTheRunningPeriod() async {
    let log = SinkRecorder()
    let rig = SupervisorRig(cursor: "c0") { options in
      options.activity = {
        Task { await log.record(.open) }
        return { Task { await log.record(.keepalive) } }
      }
    }
    #expect(await rig.connect())
    #expect(await rig.eventually { await log.events == [.open] })
    await rig.supervisor.stop()
    #expect(await rig.eventually { await log.events == [.open, .keepalive] })
  }

  @Test func startingTwiceDoesNotDoubleConnect() async {
    let rig = SupervisorRig(cursor: "c0")
    await rig.supervisor.start()
    await rig.supervisor.start()
    #expect(await rig.waitForCalls(1))
    await rig.settle()
    #expect(rig.stream.calls.count == 1)
    await rig.supervisor.stop()
  }
}

@Suite struct SupervisorRediscoveryTests {
  private func connectedRig(
    _ source: ProgrammableTopicSource
  ) async -> SupervisorRig {
    let rig = SupervisorRig(cursor: "c0", customTopics: source)
    await rig.connect()
    return rig
  }

  @Test func aTerminalRediscoveryFailureHaltsLikeAnyConnectionFailure() async {
    let source = ProgrammableTopicSource(topics: ["a"])
    await source.script(call: 2, .fail(.unauthorized))
    let rig = await connectedRig(source)
    await rig.idle(for: 1800)
    #expect(await rig.waitFor(.halted(.unauthorized)))
    await rig.supervisor.stop()
  }

  @Test func aTransientRediscoveryFailureKeepsTheConnection() async {
    let source = ProgrammableTopicSource(topics: ["a"])
    await source.script(call: 2, .fail(.serverUnreachable))
    let rig = await connectedRig(source)
    await rig.idle(for: 1800)
    #expect(await rig.eventually { await source.callCount >= 2 })
    #expect(await rig.supervisor.currentStatus == .connected)
    #expect(rig.stream.calls.count == 1)
    await rig.supervisor.stop()
  }

  @Test func aRediscoveryResultAfterAReconnectIsDropped() async {
    let source = ProgrammableTopicSource(topics: ["a"])
    await source.hold(call: 2, then: .answer(["a", "stale"]))
    let rig = await connectedRig(source)
    await rig.idle(for: 1800)
    #expect(await rig.eventually { await source.gate.waiterCount == 1 })

    rig.events.send(.didWake)
    #expect(await rig.waitForCalls(2))
    #expect(await rig.connect(connection: 2))
    await source.gate.open()
    await rig.settle()
    #expect(rig.stream.calls.count == 2)
    #expect(await rig.supervisor.currentStatus == .connected)
    await rig.supervisor.stop()
  }

  @Test func aTerminalRediscoveryFailureAfterAReconnectIsDropped() async {
    let source = ProgrammableTopicSource(topics: ["a"])
    await source.hold(call: 2, then: .fail(.unauthorized))
    let rig = await connectedRig(source)
    await rig.idle(for: 1800)
    #expect(await rig.eventually { await source.gate.waiterCount == 1 })

    rig.events.send(.didWake)
    #expect(await rig.connect(connection: 2))
    await source.gate.open()
    await rig.settle()
    #expect(await rig.supervisor.currentStatus == .connected)
    await rig.supervisor.stop()
  }
}

@Suite struct SupervisorEdgeTests {
  @Test func startAfterStopRunsAgain() async {
    let rig = SupervisorRig(cursor: "c0")
    #expect(await rig.connect())
    await rig.supervisor.stop()
    await rig.supervisor.start()
    #expect(await rig.connect(connection: 2))
    await rig.supervisor.stop()
  }

  @Test func stopTwiceAndRestartBeforeStartAreHarmless() async {
    let rig = SupervisorRig(cursor: "c0")
    await rig.supervisor.restart()
    await rig.supervisor.stop()
    #expect(await rig.supervisor.currentStatus == .stopped)
    #expect(await rig.connect())
    await rig.supervisor.stop()
    await rig.supervisor.stop()
    #expect(await rig.supervisor.currentStatus == .stopped)
    await rig.settle()
    #expect(rig.stream.calls.count == 1)
  }

  @Test func reconfigureBeforeStartAppliesAtStart() async {
    let rig = SupervisorRig(cursor: "c0")
    await rig.supervisor.reconfigure(selection: TopicSelection(extra: ["extra"]))
    await rig.settle()
    #expect(rig.stream.calls.isEmpty)
    #expect(await rig.connect())
    #expect(rig.stream.calls[0].topics == ["alpha", "extra"])
    await rig.supervisor.stop()
  }

  @Test func stopDuringDiscoveryLeavesNothingRunning() async {
    let source = ProgrammableTopicSource(topics: ["a"])
    await source.hold(call: 1, then: .answer(["a"]))
    let rig = SupervisorRig(cursor: "c0", customTopics: source)
    await rig.supervisor.start()
    #expect(await rig.eventually { await source.gate.waiterCount == 1 })
    await rig.supervisor.stop()
    #expect(await rig.supervisor.currentStatus == .stopped)
    #expect(rig.clock.sleeperCount == 0)
    #expect(rig.stream.calls.isEmpty)
  }

  @Test func stopDuringCatchUpLeavesNothingRunning() async {
    let poller = HoldingPoller()
    let rig = SupervisorRig(cursor: "c0", customPoller: poller)
    await rig.supervisor.start()
    #expect(await rig.eventually { await poller.gate.waiterCount == 1 })
    await rig.supervisor.stop()
    #expect(await rig.supervisor.currentStatus == .stopped)
    #expect(rig.clock.sleeperCount == 0)
    #expect(rig.stream.calls.isEmpty)
  }

  @Test func aPollRequestWithoutACursorFetchesNothing() async {
    let rig = SupervisorRig()
    await rig.cursor.setSaveFailure(.storage("readonly"))
    #expect(await rig.connect())
    rig.stream.send(.pollRequest)
    await rig.settle()
    #expect(await rig.poller.calls.isEmpty)
    #expect(await rig.supervisor.currentStatus == .connected)
    await rig.supervisor.stop()
  }

  @Test func aFailingCatchUpBacksOffNormally() async {
    let rig = SupervisorRig(cursor: "c0", polls: [.fail(.serverUnreachable)])
    await rig.supervisor.start()
    #expect(await rig.waitForBackoff()?.attempt == 1)
    #expect(rig.stream.calls.isEmpty)
    #expect(await rig.waitForSleepers(1))
    await rig.advance(5)
    #expect(await rig.waitForCalls(1))
    await rig.supervisor.stop()
  }

  @Test func noTopicsIsAFailureNotACrash() async {
    let rig = SupervisorRig(topics: ScriptedTopicSource(topics: []))
    await rig.supervisor.start()
    #expect(await rig.waitForBackoff()?.attempt == 1)
    #expect(rig.stream.calls.isEmpty)
    await rig.supervisor.stop()
  }

  @Test func onlyInvalidTopicNamesIsAFailureNotACrash() async {
    let rig = SupervisorRig { $0.selection = TopicSelection(override: ["not valid", ""]) }
    await rig.supervisor.start()
    #expect(await rig.waitForBackoff()?.attempt == 1)
    #expect(rig.stream.calls.isEmpty)
    await rig.supervisor.stop()
  }
}
