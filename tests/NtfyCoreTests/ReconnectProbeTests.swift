import Foundation
import NtfyCore
import Testing

/// A Mac in a dark-wake loop sleeps and wakes every minute, and its wake event can arrive late,
/// out of order or not at all. A parked machine must not depend on that one event.
@Suite struct ReconnectProbeTests {
  @Test func aSleepWhoseWakeEventNeverComesIsLeftAfterTheProbe() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    rig.send(.opened)
    #expect(rig.send(.system(.willSleep)) == .disconnect)
    #expect(rig.status == .paused)
    #expect(rig.send(.timerFired, after: 59) == nil)
    #expect(rig.status == .paused)
    #expect(rig.send(.timerFired, after: 1) == .connect)
    #expect(rig.status == .connecting)
    rig.send(.failed(.serverUnreachable))
    #expect(rig.attempt == 1)
  }

  @Test func theProbeAfterAWakeThatCameBeforeTheSleepConnects() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.opened)
    // The two workspace notifications reached the machine in the wrong order.
    rig.send(.system(.didWake))
    rig.send(.system(.willSleep))
    #expect(rig.status == .paused)
    #expect(rig.send(.timerFired, after: 60) == .connect)
  }

  @Test func theProbeConnectsWhenTheDisplaysNeverWoke() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.system(.willSleep))
    #expect(rig.send(.timerFired, after: 120) == .connect)
    #expect(rig.send(.opened) == nil)
    #expect(rig.status == .connected)
  }

  @Test func theDisplaysWakingEndsAPauseAtOnce() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.system(.willSleep))
    #expect(rig.send(.system(.screensDidWake), after: 5) == .connect)
    #expect(rig.status == .connecting)
  }

  @Test func theDisplaysWakingSkipsARunningBackoff() {
    var rig = Rig(jitter: 1)
    rig.send(.start)
    rig.send(.failed(.serverUnreachable))
    #expect(rig.delay == 5)
    #expect(rig.send(.system(.screensDidWake), after: 1) == .connect)
    rig.send(.failed(.serverUnreachable))
    #expect(rig.attempt == 1)
  }

  @Test func theDisplaysWakingLeavesALiveConnectionAlone() {
    var rig = Rig()
    rig.send(.start)
    #expect(rig.send(.system(.screensDidWake)) == nil)
    rig.send(.opened)
    #expect(rig.send(.system(.screensDidWake)) == nil)
    #expect(rig.send(.system(.screensDidSleep)) == nil)
    #expect(rig.status == .connected)
  }

  @Test func theDisplaysWakingDoesNotLeaveAHaltOrAStop() {
    var rig = Rig()
    #expect(rig.send(.system(.screensDidWake)) == nil)
    rig.send(.start)
    rig.send(.failed(.unauthorized))
    #expect(rig.send(.system(.screensDidWake)) == nil)
    #expect(rig.status == .halted(.unauthorized))
  }

  @Test func theDisplaysWakingDoesNotConnectOffline() {
    var rig = Rig(online: false)
    rig.send(.start)
    #expect(rig.send(.system(.screensDidWake)) == nil)
    #expect(rig.status == .offline)
  }

  @Test func theOfflineProbeTriesAConnectionWithoutHidingTheNetworkReturn() {
    var rig = Rig(online: false, jitter: 1)
    rig.send(.start)
    #expect(rig.status == .offline)
    #expect(rig.send(.timerFired, after: 60) == .connect)
    #expect(rig.send(.failed(.serverUnreachable), after: 1) == .disconnect)
    #expect(rig.attempt == 1)
    // The path coming back still connects at once, whatever the backoff says.
    #expect(rig.send(.system(.pathChanged(online: true)), after: 1) == .connect)
    #expect(rig.status == .connecting)
  }

  @Test func theProbeNeverFiresInAStoppedMachine() {
    var rig = Rig()
    rig.send(.start)
    rig.send(.system(.willSleep))
    rig.send(.stop)
    #expect(rig.machine.wakeUp == nil)
    #expect(rig.send(.timerFired, after: 600) == nil)
  }
}
