import Foundation
import NtfyCore
import NtfyTesting
import Testing

@Suite struct MeetingPolicyTests {
  private let clock = FakeClock()
  private let zoomOn = MeetingSnapshot(
    audio: [
      AudioProcessState(
        pid: 1, bundleID: "us.zoom.xos", isRunningInput: true, isRunningOutput: true)
    ])
  private let quiet = MeetingSnapshot()
  private let unreadable = MeetingSnapshot(audio: nil)

  private func step(
    _ policy: inout MeetingPolicy, _ snapshot: MeetingSnapshot, after seconds: Double = 0
  ) -> MeetingState {
    clock.advance(by: .seconds(seconds))
    return policy.evaluate(snapshot, at: clock.now())
  }

  @Test func aSignalMustHoldForTheDwellBeforeTheMeetingStarts() {
    var policy = MeetingPolicy()
    #expect(step(&policy, zoomOn) == .inactive)
    #expect(step(&policy, zoomOn, after: 2.9) == .inactive)
    #expect(step(&policy, zoomOn, after: 0.1) == .active(.app("Zoom")))
  }

  @Test func aBlipShorterThanTheDwellNeverStartsAMeeting() {
    var policy = MeetingPolicy()
    #expect(step(&policy, zoomOn) == .inactive)
    #expect(step(&policy, quiet, after: 1) == .inactive)
    #expect(step(&policy, zoomOn, after: 1) == .inactive)
    #expect(step(&policy, zoomOn, after: 2) == .inactive)
    #expect(step(&policy, zoomOn, after: 1) == .active(.app("Zoom")))
  }

  @Test func theMeetingEndsOnlyAfterTheReleaseLatch() {
    var policy = MeetingPolicy()
    _ = step(&policy, zoomOn)
    _ = step(&policy, zoomOn, after: 3)
    #expect(step(&policy, quiet, after: 10) == .active(.app("Zoom")))
    #expect(step(&policy, quiet, after: 34.9) == .active(.app("Zoom")))
    #expect(step(&policy, quiet, after: 0.1) == .inactive)
  }

  @Test func aMuteInTheMiddleOfACallDoesNotEndIt() {
    var policy = MeetingPolicy()
    _ = step(&policy, zoomOn)
    _ = step(&policy, zoomOn, after: 3)
    #expect(step(&policy, quiet, after: 30) == .active(.app("Zoom")))
    #expect(step(&policy, zoomOn, after: 5) == .active(.app("Zoom")))
    #expect(step(&policy, quiet, after: 40) == .active(.app("Zoom")))
  }

  @Test func theLatchRestartsFromTheLastSignal() {
    var policy = MeetingPolicy()
    _ = step(&policy, zoomOn)
    _ = step(&policy, zoomOn, after: 3)
    _ = step(&policy, quiet, after: 40)
    _ = step(&policy, zoomOn, after: 4)
    #expect(step(&policy, quiet, after: 44) == .active(.app("Zoom")))
    #expect(step(&policy, quiet, after: 1) == .inactive)
  }

  @Test func anUnreadableReadingChangesNothing() {
    var policy = MeetingPolicy()
    #expect(step(&policy, unreadable) == .inactive)
    _ = step(&policy, zoomOn)
    _ = step(&policy, zoomOn, after: 3)
    #expect(step(&policy, unreadable, after: 600) == .active(.app("Zoom")))
  }

  @Test func theReasonFollowsTheSignal() {
    var policy = MeetingPolicy()
    let huddle = MeetingSnapshot(
      audio: [
        AudioProcessState(
          pid: 2, bundleID: "com.tinyspeck.slackmacgap", isRunningInput: true,
          isRunningOutput: true)
      ])
    _ = step(&policy, zoomOn)
    _ = step(&policy, zoomOn, after: 3)
    #expect(step(&policy, huddle, after: 1) == .active(.slackHuddle))
  }

  @Test func theDeadlineNamesTheNextTimeTheStateMayChange() {
    var policy = MeetingPolicy()
    #expect(policy.nextDeadline == nil)
    let start = clock.now()
    _ = step(&policy, zoomOn)
    #expect(policy.nextDeadline == start.addingTimeInterval(3))
    _ = step(&policy, zoomOn, after: 3)
    #expect(policy.nextDeadline == clock.now().addingTimeInterval(45))
    _ = step(&policy, quiet, after: 45)
    #expect(policy.nextDeadline == nil)
  }

  @Test func aZeroDwellStartsAtOnce() {
    var policy = MeetingPolicy(dwell: 0)
    #expect(step(&policy, zoomOn) == .active(.app("Zoom")))
  }
}
