import Foundation
import NtfyCore
import NtfyTesting
import Testing

@Suite struct SupervisorSystemEventTests {
  @Test func sleepThenWakeReconnectsAtOnceAndCatchesUp() async throws {
    let rig = SupervisorRig(cursor: "c0")
    #expect(await rig.connect())
    rig.events.send(.willSleep)
    #expect(await rig.waitFor(.paused))
    #expect(await rig.waitForSleepers(0))
    #expect(await rig.eventually { rig.stream.liveConnectionCount == 0 })

    rig.events.send(.didWake)
    #expect(await rig.waitForCalls(2))
    #expect(rig.stream.calls[1].since == "c0")
    #expect(await rig.poller.calls.count == 2)
    #expect(await rig.connect(connection: 2))
    await rig.supervisor.stop()
  }

  @Test func wakeSkipsARunningBackoff() async {
    let rig = SupervisorRig(cursor: "c0")
    await rig.supervisor.start()
    #expect(await rig.waitForCalls(1))
    rig.stream.fail(.serverUnreachable)
    #expect(await rig.waitForBackoff() != nil)
    rig.events.send(.willSleep)
    #expect(await rig.waitFor(.paused))
    rig.events.send(.didWake)
    #expect(await rig.waitForCalls(2))
    await rig.supervisor.stop()
  }

  @Test func lostPathGoesOfflineAndTheReturnConnects() async {
    let rig = SupervisorRig(cursor: "c0")
    #expect(await rig.connect())
    rig.events.send(.pathChanged(online: false))
    #expect(await rig.waitFor(.offline))
    #expect(await rig.waitForSleepers(0))
    #expect(await rig.eventually { rig.stream.liveConnectionCount == 0 })

    await rig.advance(3600)
    #expect(rig.stream.calls.count == 1)
    #expect(await rig.supervisor.currentStatus == .offline)

    rig.events.send(.pathChanged(online: true))
    #expect(await rig.waitForCalls(2))
    await rig.supervisor.stop()
  }

  @Test func startingOfflineWaitsWithoutConnectingOrFailing() async {
    let rig = SupervisorRig { $0.initiallyOnline = false }
    await rig.supervisor.start()
    #expect(await rig.waitFor(.offline))
    await rig.advance(86_400)
    #expect(rig.stream.calls.isEmpty)
    #expect(await rig.topics.callCount == 0)
    #expect(rig.clock.sleeperCount == 0)

    rig.events.send(.pathChanged(online: true))
    #expect(await rig.connect())
    await rig.supervisor.stop()
  }

  @Test func offlineLearnedAfterStartCancelsTheAttemptWithoutBackoff() async {
    let rig = SupervisorRig(cursor: "c0")
    await rig.supervisor.start()
    rig.events.send(.pathChanged(online: false))
    #expect(await rig.waitFor(.offline))
    await rig.advance(3600)
    #expect(await rig.supervisor.currentStatus == .offline)
    await rig.supervisor.stop()
  }
}

@Suite struct SupervisorFailureTests {
  @Test func unauthorizedHaltsWithoutRetriesAndRestartRecovers() async {
    let rig = SupervisorRig(cursor: "c0")
    await rig.supervisor.start()
    #expect(await rig.waitForCalls(1))
    rig.stream.fail(.unauthorized)
    #expect(await rig.waitFor(.halted(.unauthorized)))
    #expect(await rig.waitForSleepers(0))

    await rig.advance(86_400)
    #expect(rig.stream.calls.count == 1)

    await rig.supervisor.restart()
    #expect(await rig.connect(connection: 2))
    await rig.supervisor.stop()
  }

  @Test func redirectHalts() async {
    let rig = SupervisorRig(cursor: "c0")
    await rig.supervisor.start()
    #expect(await rig.waitForCalls(1))
    rig.stream.fail(.redirected)
    #expect(await rig.waitFor(.halted(.redirected)))
    await rig.advance(86_400)
    #expect(rig.stream.calls.count == 1)
    await rig.supervisor.stop()
  }

  @Test func discoveryRejectedByTheServerHaltsToo() async {
    let rig = SupervisorRig(topics: ScriptedTopicSource(failingWith: .unauthorized))
    await rig.supervisor.start()
    #expect(await rig.waitFor(.halted(.unauthorized)))
    #expect(rig.stream.calls.isEmpty)
    await rig.supervisor.stop()
  }

  @Test func discoveryOutageBacksOffAndRetries() async {
    let rig = SupervisorRig(topics: ScriptedTopicSource(failingWith: .serverUnreachable))
    await rig.supervisor.start()
    #expect(await rig.waitForBackoff()?.attempt == 1)
    #expect(await rig.waitForSleepers(1))
    await rig.advance(5)
    #expect(await rig.eventually { await rig.topics.callCount == 2 })
    await rig.supervisor.stop()
  }

  @Test func rateLimitWaitsAtLeastRetryAfter() async throws {
    let rig = SupervisorRig(cursor: "c0")
    let started = rig.clock.now()
    await rig.supervisor.start()
    #expect(await rig.waitForCalls(1))
    rig.stream.fail(.rateLimited(retryAfter: 120))
    let backoff = try #require(await rig.waitForBackoff())
    #expect(backoff.until.timeIntervalSince(started) >= 120)
    #expect(await rig.waitForSleepers(1))

    await rig.advance(119)
    #expect(rig.stream.calls.count == 1)
    await rig.advance(1)
    #expect(await rig.waitForCalls(2))
    await rig.supervisor.stop()
  }

  @Test func transientFailuresBackOffWithGrowingDelays() async throws {
    let rig = SupervisorRig(cursor: "c0")
    await rig.supervisor.start()
    var delays: [TimeInterval] = []
    for connection in 1...3 {
      #expect(await rig.waitForCalls(connection))
      let before = rig.clock.now()
      rig.stream.fail(.serverUnreachable)
      let backoff = try #require(await rig.waitForBackoff())
      delays.append(backoff.until.timeIntervalSince(before))
      #expect(await rig.waitForSleepers(1))
      await rig.advance(delays.last ?? 0)
    }
    #expect(delays == [5, 10, 20])
    await rig.supervisor.stop()
  }
}

@Suite struct SupervisorWatchdogTests {
  @Test func silenceForNinetySecondsIsAStallAndReconnects() async throws {
    let rig = SupervisorRig(cursor: "c0")
    #expect(await rig.connect())
    await rig.advance(89)
    #expect(await rig.supervisor.currentStatus == .connected)
    await rig.advance(1)
    let backoff = try #require(await rig.waitForBackoff())
    #expect(backoff.attempt == 1)
    #expect(await rig.eventually { rig.stream.liveConnectionCount == 0 })

    #expect(await rig.waitForSleepers(1))
    await rig.advance(5)
    #expect(await rig.waitForCalls(2))
    await rig.supervisor.stop()
  }

  @Test func theDeadlineScalesWithTheObservedKeepaliveGap() async throws {
    let rig = SupervisorRig(cursor: "c0")
    #expect(await rig.connect())
    await rig.advance(80)
    rig.stream.send(.keepalive)
    await rig.settle()

    await rig.advance(100)
    #expect(await rig.supervisor.currentStatus == .connected)
    #expect(await rig.waitForSleepers(2))
    await rig.advance(59)
    #expect(await rig.supervisor.currentStatus == .connected)
    await rig.advance(1)
    #expect(await rig.waitForBackoff() != nil)
    await rig.supervisor.stop()
  }

  @Test func keepalivesKeepAConnectionAlive() async {
    let rig = SupervisorRig(cursor: "c0")
    #expect(await rig.connect())
    await rig.idle(for: 45 * 6)
    #expect(await rig.supervisor.currentStatus == .connected)
    #expect(rig.stream.calls.count == 1)
    await rig.supervisor.stop()
  }
}

@Suite struct SupervisorReconnectTests {
  @Test func aCleanFinishAfterAHealthyPeriodReconnectsWithTheCursor() async throws {
    let rig = SupervisorRig(cursor: "c0")
    #expect(await rig.connect())
    rig.stream.send(rig.message("m1"))
    #expect(await rig.eventually { await rig.cursor.load() == "m1" })
    await rig.advance(60)
    rig.stream.finish()
    let backoff = try #require(await rig.waitForBackoff())
    #expect(backoff.attempt == 0)
    #expect(await rig.waitForSleepers(1))
    await rig.advance(1)
    #expect(await rig.waitForCalls(2))
    #expect(rig.stream.calls[1].since == "m1")
    await rig.supervisor.stop()
  }

  @Test func theBackoffResetsAfterAHealthyConnectionButNotAfterAQuickDrop() async throws {
    let rig = SupervisorRig(cursor: "c0")
    await rig.supervisor.start()
    #expect(await rig.waitForCalls(1))
    rig.stream.fail(.serverUnreachable)
    #expect(await rig.waitForBackoff()?.attempt == 1)
    #expect(await rig.waitForSleepers(1))
    await rig.advance(5)

    #expect(await rig.connect(connection: 2))
    await rig.advance(30)
    rig.stream.fail(.serverUnreachable)
    try #require(await rig.eventually { await rig.supervisor.currentStatus != .connected })
    #expect(await rig.waitForBackoff()?.attempt == 2)
    #expect(await rig.waitForSleepers(1))
    await rig.advance(10)

    #expect(await rig.connect(connection: 3))
    rig.stream.send(.keepalive)
    await rig.idle(for: 90)
    rig.stream.fail(.serverUnreachable)
    #expect(await rig.waitForBackoff()?.attempt == 1)
    await rig.supervisor.stop()
  }

  @Test func aChangedTopicSetTriggersAReconnect() async {
    let source = ScriptedTopicSource(topics: ["a"])
    let rig = SupervisorRig(cursor: "c0", topics: source)
    #expect(await rig.connect())
    await rig.idle(for: 1800)
    #expect(rig.stream.calls.count == 1)
    #expect(await rig.eventually { await source.callCount >= 2 })
    // The next rediscovery round must be waiting on the clock before time moves again.
    #expect(await rig.waitForSleepers(2))

    await source.setTopics(["a", "b"])
    await rig.idle(for: 1800)
    #expect(await rig.waitForCalls(2))
    #expect(rig.stream.calls[1].topics == ["a", "b"])
    await rig.supervisor.stop()
  }

  @Test func reconfigureReconnectsWithTheNewSelection() async {
    let rig = SupervisorRig(cursor: "c0")
    #expect(await rig.connect())
    await rig.supervisor.reconfigure(selection: TopicSelection(extra: ["extra"]))
    #expect(await rig.waitForCalls(2))
    #expect(rig.stream.calls[1].topics == ["alpha", "extra"])
    await rig.supervisor.stop()
  }

  @Test func reconfigureWithAnOverrideSkipsDiscoveryAndRediscovery() async {
    let rig = SupervisorRig(cursor: "c0") { $0.selection = TopicSelection(override: ["only"]) }
    #expect(await rig.connect())
    #expect(rig.stream.calls[0].topics == ["only"])
    #expect(await rig.topics.callCount == 0)
    #expect(await rig.waitForSleepers(1))
    await rig.supervisor.stop()
  }

  @Test func reconfigureCanLeaveAHaltCausedByATopic() async {
    let rig = SupervisorRig(cursor: "c0")
    await rig.supervisor.start()
    #expect(await rig.waitForCalls(1))
    rig.stream.fail(.invalidTopic("alpha"))
    #expect(await rig.waitFor(.halted(.invalidTopic("alpha"))))
    await rig.supervisor.reconfigure(selection: TopicSelection(override: ["fixed"]))
    #expect(await rig.waitForCalls(2))
    #expect(rig.stream.calls[1].topics == ["fixed"])
    await rig.supervisor.stop()
  }
}
