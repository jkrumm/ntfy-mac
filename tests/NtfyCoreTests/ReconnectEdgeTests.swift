import NtfyCore
import Testing

@Suite struct ReconnectEdgeTests {
  @Test func aSecondStartChangesNothing() {
    var rig = Rig()
    #expect(rig.send(.start) == .connect)
    rig.send(.opened)
    #expect(rig.send(.start) == nil)
    #expect(rig.status == .connected)
  }

  @Test func stopWhileBackingOffCancelsTheTimer() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    rig.send(.failed(.serverUnreachable))
    #expect(rig.send(.stop) == .disconnect)
    #expect(rig.status == .stopped)
    #expect(rig.machine.wakeUp == nil)
    #expect(rig.send(.timerFired, after: 1000) == nil)
  }

  @Test func aCleanFinishWhileConnectingCountsAsAFailure() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    #expect(rig.send(.finished, after: 1) == .disconnect)
    #expect(rig.attempt == 1)
    #expect(rig.delay == 5)
  }

  @Test func wakeWhileHaltedIsIgnoredEvenAfterASleep() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.failed(.unauthorized))
    #expect(rig.send(.system(.willSleep)) == nil)
    #expect(rig.send(.system(.didWake)) == nil)
    #expect(rig.status == .halted(.unauthorized))
  }

  @Test func backoffNeverExceedsTheCapForManyAttemptsAndAnyJitter() {
    for jitter in [-3.0, 0, 0.001, 0.5, 0.999, 1, 42] {
      var rig = Rig(jitter: jitter)
      rig.send(.start)
      for _ in 0..<200 {
        rig.send(.failed(.serverUnreachable))
        let delay = rig.delay ?? -1
        #expect(delay >= 2.5 && delay <= 300)
        rig.send(.timerFired, after: delay)
      }
    }
  }

  @Test func rateLimitNeverExceedsItsCapForManyAttempts() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    for retryAfter in stride(from: 0, to: 20_000, by: 250) {
      rig.send(.failed(.rateLimited(retryAfter: retryAfter)))
      let delay = rig.delay ?? -1
      #expect(delay >= 60 && delay <= 3600)
      #expect(delay >= Double(min(retryAfter, 3600)))
      rig.send(.timerFired, after: delay)
    }
  }
}
