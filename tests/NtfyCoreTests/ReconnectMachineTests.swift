import Foundation
import NtfyCore
import Testing

@Suite struct ReconnectBackoffTests {
  @Test func delaysDoubleFromFiveSecondsAndStopAtFiveMinutes() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    var delays: [TimeInterval] = []
    for _ in 0..<9 {
      rig.send(.failed(.serverUnreachable))
      delays.append(rig.delay ?? -1)
      #expect(rig.send(.timerFired, after: rig.delay ?? 0) == .connect)
    }
    #expect(delays == [5, 10, 20, 40, 80, 160, 300, 300, 300])
  }

  @Test func attemptCountsConsecutiveFailures() {
    var rig = Rig()
    rig.send(.start)
    for expected in 1...3 {
      rig.send(.failed(.invalidResponse("x")))
      #expect(rig.attempt == expected)
      rig.send(.timerFired, after: rig.delay ?? 0)
    }
  }

  @Test(arguments: [0.0, 0.25, 0.5, 0.75, 1.0])
  func jitterKeepsTheDelayBetweenHalfAndFullBackoff(jitter: Double) {
    var rig = Rig(jitter: jitter)
    rig.send(.start)
    rig.send(.failed(.serverUnreachable))
    let delay = rig.delay ?? -1
    #expect(delay >= 2.5)
    #expect(delay <= 5)
    #expect(abs(delay - (2.5 + 2.5 * jitter)) < 0.0001)
  }

  @Test func jitterOutsideTheUnitRangeIsClamped() {
    var rig = Rig(jitter: 7)
    rig.send(.start)
    rig.send(.failed(.serverUnreachable))
    #expect(rig.delay == 5)
  }

  @Test func timerBeforeTheDeadlineDoesNothing() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    rig.send(.failed(.serverUnreachable))
    #expect(rig.send(.timerFired, after: 4.9) == nil)
    #expect(rig.send(.timerFired, after: 0.2) == .connect)
  }

  @Test func resetsOnlyAfterAHealthyPeriod() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    for _ in 0..<3 {
      rig.send(.failed(.serverUnreachable))
      rig.send(.timerFired, after: rig.delay ?? 0)
    }
    rig.send(.opened, after: 1)
    rig.send(.failed(.serverUnreachable), after: 60)
    #expect(rig.attempt == 1)
    #expect(rig.delay == 5)
  }

  @Test func aConnectionThatDropsQuicklyKeepsTheBackoffGrowing() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    rig.send(.failed(.serverUnreachable))
    rig.send(.timerFired, after: rig.delay ?? 0)
    rig.send(.opened, after: 1)
    rig.send(.failed(.serverUnreachable), after: 59)
    #expect(rig.attempt == 2)
    #expect(rig.delay == 10)
  }

  @Test func aMessageDoesNotResetTheBackoff() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    rig.send(.failed(.serverUnreachable))
    rig.send(.timerFired, after: rig.delay ?? 0)
    rig.send(.opened, after: 1)
    rig.send(.activity, after: 5)
    rig.send(.failed(.serverUnreachable), after: 5)
    #expect(rig.attempt == 2)
  }

  @Test func serverTroubleBacksOffNormally() {
    for error in [NtfyError.serverUnreachable, .invalidResponse("garbage")] {
      var rig = Rig(jitter: 1)
      rig.send(.start)
      #expect(rig.send(.failed(error)) == .disconnect)
      #expect(rig.delay == 5)
    }
  }

  @Test func cleanFinishAfterAHealthyConnectionReconnectsQuicklyWithoutCountingAFailure() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    rig.send(.failed(.serverUnreachable))
    rig.send(.timerFired, after: rig.delay ?? 0)
    rig.send(.opened, after: 1)
    rig.send(.finished, after: 120)
    #expect(rig.attempt == 0)
    #expect(rig.delay == 1)
    #expect(rig.send(.timerFired, after: 1) == .connect)
  }

  @Test func cleanFinishRightAfterOpenCountsAsAFailureSoItCannotLoopFast() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    rig.send(.opened, after: 1)
    rig.send(.finished, after: 2)
    #expect(rig.attempt == 1)
    #expect(rig.delay == 5)
  }
}

@Suite struct ReconnectTerminalTests {
  @Test(arguments: [
    NtfyError.unauthorized, .redirected, .invalidTopic("bad topic"), .insecureServer,
  ])
  func terminalErrorsHaltWithoutRetry(error: NtfyError) {
    var rig = Rig()
    rig.send(.start)
    #expect(rig.send(.failed(error)) == .disconnect)
    #expect(rig.status == .halted(error))
    #expect(rig.machine.wakeUp == nil)
    #expect(rig.send(.timerFired, after: 10_000) == nil)
    #expect(rig.send(.system(.didWake)) == nil)
    #expect(rig.send(.system(.pathChanged(online: false))) == nil)
    #expect(rig.send(.system(.pathChanged(online: true))) == nil)
    #expect(rig.status == .halted(error))
  }

  @Test func restartLeavesAHaltAndConnects() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.failed(.unauthorized))
    #expect(rig.send(.restart) == .connect)
    #expect(rig.status == .connecting)
  }

  @Test func restartWhileOfflineWaitsForTheNetwork() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.failed(.unauthorized))
    rig.send(.system(.pathChanged(online: false)))
    rig.send(.restart)
    #expect(rig.status == .offline)
    #expect(rig.send(.system(.pathChanged(online: true))) == .connect)
  }

  @Test func rateLimitWaitsAtLeastRetryAfter() {
    var rig = Rig(jitter: 0)
    rig.send(.start)
    rig.send(.failed(.rateLimited(retryAfter: 600)))
    #expect(rig.delay == 600)
    #expect(rig.attempt == 1)
  }

  @Test func rateLimitWaitsAtLeastAMinuteEvenForASmallOrMissingRetryAfter() {
    for retryAfter in [nil, 0, 3, -5] {
      var rig = Rig(jitter: 0)
      rig.send(.start)
      rig.send(.failed(.rateLimited(retryAfter: retryAfter)))
      #expect(rig.delay == 60)
    }
  }

  @Test func rateLimitDelayIsCapped() {
    var rig = Rig(jitter: 0)
    rig.send(.start)
    rig.send(.failed(.rateLimited(retryAfter: 1_000_000)))
    #expect(rig.delay == 3600)
  }
}

@Suite struct ReconnectWatchdogTests {
  @Test func silenceOfNinetySecondsIsAStall() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    rig.send(.opened)
    #expect(rig.machine.wakeUp == rig.now.addingTimeInterval(90))
    #expect(rig.send(.timerFired, after: 89) == nil)
    #expect(rig.status == .connected)
    #expect(rig.send(.timerFired, after: 1) == .disconnect)
    #expect(rig.attempt == 1)
  }

  @Test func theDeadlineScalesWithTheLargestGapBetweenEvents() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.opened)
    rig.send(.activity, after: 80)
    #expect(rig.machine.wakeUp == rig.now.addingTimeInterval(160))
    rig.send(.activity, after: 10)
    #expect(rig.machine.wakeUp == rig.now.addingTimeInterval(160))
  }

  @Test func smallGapsKeepTheFloor() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.opened)
    rig.send(.activity, after: 20)
    #expect(rig.machine.wakeUp == rig.now.addingTimeInterval(90))
  }

  @Test func theDeadlineIsCapped() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.opened)
    rig.send(.activity, after: 5000)
    #expect(rig.machine.wakeUp == rig.now.addingTimeInterval(900))
  }

  @Test func anAttemptWithoutAnySignOfLifeTimesOut() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    #expect(rig.machine.wakeUp == rig.now.addingTimeInterval(90))
    #expect(rig.send(.timerFired, after: 90) == .disconnect)
    #expect(rig.attempt == 1)
  }

  @Test func activityBeforeOpenCountsAsConnected() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.activity, after: 1)
    #expect(rig.status == .connected)
  }

  @Test func eventsFromACancelledConnectionAreIgnored() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.system(.willSleep))
    #expect(rig.send(.failed(.serverUnreachable)) == nil)
    #expect(rig.send(.finished) == nil)
    #expect(rig.send(.opened) == nil)
    #expect(rig.status == .paused)
  }
}

@Suite struct ReconnectSystemEventTests {
  @Test func sleepPausesAndWakeConnectsAtOnceSkippingBackoff() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    rig.send(.failed(.serverUnreachable))
    rig.send(.timerFired, after: rig.delay ?? 0)
    rig.send(.failed(.serverUnreachable))
    #expect(rig.attempt == 2)
    #expect(rig.send(.system(.willSleep)) == .disconnect)
    #expect(rig.status == .paused)
    #expect(rig.machine.wakeUp == nil)
    #expect(rig.send(.system(.didWake), after: 3600) == .connect)
    #expect(rig.status == .connecting)
  }

  @Test func wakeReconnectsAConnectionThatLooksAlive() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.opened)
    #expect(rig.send(.system(.didWake)) == .connect)
  }

  @Test func sleepIsNotAFailure() {
    var rig = Rig(jitter: 1)
    rig.connectAndStayUp(for: 1)
    rig.send(.system(.willSleep))
    rig.send(.system(.didWake))
    rig.send(.failed(.serverUnreachable))
    #expect(rig.attempt == 1)
  }

  @Test func lostPathGoesOfflineWithoutFailureAndTheReturnConnectsAtOnce() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    rig.send(.opened)
    #expect(rig.send(.system(.pathChanged(online: false))) == .disconnect)
    #expect(rig.status == .offline)
    #expect(rig.machine.wakeUp == nil)
    #expect(rig.send(.timerFired, after: 10_000) == nil)
    #expect(rig.send(.system(.pathChanged(online: true))) == .connect)
    rig.send(.failed(.serverUnreachable))
    #expect(rig.attempt == 1)
  }

  @Test func pathReturnSkipsARunningBackoff() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    rig.send(.failed(.serverUnreachable))
    rig.send(.system(.pathChanged(online: false)))
    #expect(rig.send(.system(.pathChanged(online: true))) == .connect)
  }

  @Test func startingOfflineParksInsteadOfFailing() {
    var rig = Rig(online: false)
    #expect(rig.send(.start) == .disconnect)
    #expect(rig.status == .offline)
    #expect(rig.send(.timerFired, after: 100_000) == nil)
    #expect(rig.send(.system(.didWake)) == .disconnect)
    #expect(rig.status == .offline)
    #expect(rig.send(.system(.pathChanged(online: true))) == .connect)
  }

  @Test func offlineAtStartupLearnedFromTheFirstPathEvent() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.system(.pathChanged(online: false)))
    #expect(rig.status == .offline)
  }

  @Test func aRepeatedOnlinePathEventKeepsTheConnection() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.opened)
    #expect(rig.send(.system(.pathChanged(online: true))) == nil)
    #expect(rig.status == .connected)
  }

  @Test func wakingWhileOfflineStaysOffline() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.system(.willSleep))
    rig.send(.system(.pathChanged(online: false)))
    #expect(rig.status == .paused)
    #expect(rig.send(.system(.didWake)) == .disconnect)
    #expect(rig.status == .offline)
  }

  @Test func theNetworkReturningWhileAsleepWaitsForWake() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.system(.willSleep))
    #expect(rig.send(.system(.pathChanged(online: true))) == nil)
    #expect(rig.status == .paused)
  }

  @Test func systemEventsBeforeStartOrAfterStopDoNotConnect() {
    var rig = Rig()
    #expect(rig.send(.system(.didWake)) == nil)
    #expect(rig.status == .stopped)
    rig.send(.start)
    rig.send(.stop)
    #expect(rig.status == .stopped)
    #expect(rig.send(.system(.didWake)) == nil)
    #expect(rig.send(.timerFired, after: 1000) == nil)
  }

  @Test func reconnectOnlyActsOnAConnectedMachine() {
    var rig = Rig()
    #expect(rig.send(.reconnect) == nil)
    rig.send(.start)
    #expect(rig.send(.reconnect) == nil)
    rig.send(.opened)
    #expect(rig.send(.reconnect) == .connect)
  }
}
