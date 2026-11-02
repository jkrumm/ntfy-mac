import Testing

@testable import NtfyCore

@Suite struct MeetingClassifierTests {
  private func process(
    _ bundleID: String, pid: Int32 = 100, input: Bool = false, output: Bool = false
  ) -> AudioProcessState {
    AudioProcessState(pid: pid, bundleID: bundleID, isRunningInput: input, isRunningOutput: output)
  }

  private func verdict(
    _ audio: [AudioProcessState]?, camera: CameraState = .idle, running: Set<String> = [],
    own: Int32? = nil
  ) -> MeetingVerdict {
    MeetingClassifier.verdict(
      for: MeetingSnapshot(
        audio: audio, camera: camera, runningApps: running, ownPID: own))
  }

  @Test func nothingRunningIsNoMeeting() {
    #expect(verdict([]) == .none)
  }

  @Test(arguments: [
    ("us.zoom.xos", "Zoom"), ("com.microsoft.teams2", "Microsoft Teams"),
    ("com.microsoft.teams", "Microsoft Teams"), ("Cisco-Systems.Spark", "Webex"),
    ("com.apple.FaceTime", "FaceTime"),
  ])
  func aMeetingAppHoldingTheMicrophoneIsAMeeting(bundleID: String, name: String) {
    #expect(verdict([process(bundleID, input: true)]) == .meeting(.app(name)))
  }

  @Test func aMeetingAppThatOnlyPlaysAudioIsNoMeeting() {
    #expect(verdict([process("us.zoom.xos", output: true)]) == .none)
  }

  @Test func aTeamsHelperCountsThroughThePrefix() {
    let helper = process("com.microsoft.teams2.modulehost", input: true)
    #expect(verdict([helper]) == .meeting(.app("Microsoft Teams")))
  }

  @Test func theDotBoundaryKeepsLookalikesOut() {
    #expect(verdict([process("us.zoom.xosmos", input: true)]) == .none)
    #expect(verdict([process("com.google.Chromium", input: true)], camera: .running) == .none)
  }

  // MARK: Slack

  @Test func slackWithOnlyOutputIsIdle() {
    #expect(verdict([process("com.tinyspeck.slackmacgap", output: true)]) == .none)
  }

  @Test func slackWithOnlyInputIsIdle() {
    #expect(verdict([process("com.tinyspeck.slackmacgap", input: true)]) == .none)
  }

  @Test func slackWithBothIsAHuddle() {
    let audio = [process("com.tinyspeck.slackmacgap", input: true, output: true)]
    #expect(verdict(audio) == .meeting(.slackHuddle))
  }

  @Test func slackHelpersAddUpToAHuddle() {
    let audio = [
      process("com.tinyspeck.slackmacgap.helper", pid: 1, input: true),
      process("com.tinyspeck.slackmacgap", pid: 2, output: true),
    ]
    #expect(verdict(audio) == .meeting(.slackHuddle))
  }

  @Test func inputOfOneAppAndOutputOfAnotherIsNoHuddle() {
    let audio = [
      process("com.tinyspeck.slackmacgap", input: true),
      process("com.spotify.client", pid: 2, output: true),
    ]
    #expect(verdict(audio) == .none)
  }

  // MARK: Browsers and the camera

  @Test func aBrowserHelperWithMicrophoneAndCameraIsACall() {
    let audio = [process("com.google.Chrome.helper", input: true)]
    #expect(verdict(audio, camera: .running) == .meeting(.browserCall("Google Chrome")))
  }

  @Test func aBrowserWithMicrophoneButNoCameraIsNoMeeting() {
    #expect(verdict([process("com.google.Chrome.helper", input: true)], camera: .idle) == .none)
  }

  @Test func aBrowserPlayingAudioWithTheCameraRunningIsNoMeeting() {
    #expect(verdict([process("com.google.Chrome.helper", output: true)], camera: .running) == .none)
  }

  @Test func theCameraAloneIsNoMeeting() {
    #expect(verdict([], camera: .running) == .none)
  }

  @Test func aBrowserWithMicrophoneAndAnUnreadableCameraIsUnknown() {
    #expect(
      verdict([process("com.google.Chrome.helper", input: true)], camera: .unknown) == .unknown)
  }

  @Test func anUnreadableCameraDoesNotHideAMeetingApp() {
    let audio = [process("us.zoom.xos", input: true)]
    #expect(verdict(audio, camera: .unknown) == .meeting(.app("Zoom")))
  }

  @Test func anUnreadableCameraWithNoBrowserInputIsNoMeeting() {
    #expect(verdict([process("us.zoom.xos", output: true)], camera: .unknown) == .none)
  }

  @Test func safariIsRecognisedByItsSharedGPUProcessOnlyWhileSafariRuns() {
    let audio = [process("com.apple.WebKit.GPU", input: true)]
    #expect(
      verdict(audio, camera: .running, running: ["com.apple.Safari"])
        == .meeting(.browserCall("Safari")))
    #expect(verdict(audio, camera: .running, running: []) == .none)
  }

  // MARK: Exclusions and unknown readings

  @Test(arguments: ["com.apple.CoreSpeech", "com.apple.Siri", "com.apple.assistantd"])
  func systemMicrophoneUsersNeverCount(bundleID: String) {
    #expect(verdict([process(bundleID, input: true)], camera: .running) == .none)
  }

  @Test func theAppItselfNeverCounts() {
    #expect(verdict([process("us.zoom.xos", pid: 42, input: true)], own: 42) == .none)
    #expect(verdict([process("com.jkrumm.ntfy-mac", pid: 7, input: true)]) == .none)
  }

  @Test func anUnrelatedProcessWithoutABundleIsIgnored() {
    #expect(verdict([process("", input: true, output: true)], camera: .running) == .none)
  }

  @Test func anUnreadableAudioListIsUnknown() {
    #expect(verdict(nil) == .unknown)
  }
}
