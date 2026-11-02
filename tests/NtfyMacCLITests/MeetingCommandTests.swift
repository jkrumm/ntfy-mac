import Foundation
import NtfyCore
import NtfyIPC
import Testing

@testable import NtfyMacCLI

@Suite struct MeetingCommandTests {
  // MARK: config meeting

  @Test func theDefaultIsOffWithTheBypassOn() async throws {
    let json = try await CLIRig().run("config", "meeting", "--json").json()
    #expect(json["mode"] as? String == "off")
    #expect(json["urgentBypass"] as? Bool == true)
    #expect(json["presenting"] as? Bool == false)
  }

  @Test func setChangesOnlyWhatIsGiven() async {
    let rig = CLIRig()
    #expect(await rig.run("config", "meeting", "set", "--mode", "pause").exit == .success)
    #expect(await rig.config.load().meeting == MeetingSettings(mode: .pause))
    #expect(await rig.run("config", "meeting", "set", "--no-urgent-bypass").exit == .success)
    #expect(
      await rig.config.load().meeting == MeetingSettings(mode: .pause, urgentBypass: false))
    #expect(await rig.run("config", "meeting", "set", "--urgent-bypass").exit == .success)
    #expect(await rig.config.load().meeting == MeetingSettings(mode: .pause))
  }

  @Test func setNeedsSomethingToChangeAndRejectsContradictionsAndUnknownModes() async {
    let rig = CLIRig()
    #expect(await rig.run("config", "meeting", "set").exit == .usage)
    #expect(
      await rig.run("config", "meeting", "set", "--urgent-bypass", "--no-urgent-bypass").exit
        == .usage)
    #expect(await rig.run("config", "meeting", "set", "--mode", "always").exit == .usage)
  }

  @Test func resetRestoresTheDefaultsAndKeepsAnActiveOverride() async {
    let rig = CLIRig()
    let until = rig.clock.now().addingTimeInterval(600)
    await rig.config.update {
      $0.meeting = MeetingSettings(mode: .pause, urgentBypass: false, presentingUntil: until)
    }
    #expect(await rig.run("config", "meeting", "reset").exit == .success)
    #expect(await rig.config.load().meeting == MeetingSettings(presentingUntil: until))
  }

  @Test func configLeavesOtherKeysAlone() async {
    let rig = CLIRig()
    await rig.config.update { $0.extraTopics = ["mine"] }
    _ = await rig.run("config", "meeting", "set", "--mode", "pause")
    #expect(await rig.config.load().extraTopics == ["mine"])
  }

  // MARK: present

  @Test func presentOnWithoutALimitIsIndefiniteAndOffClearsIt() async throws {
    let rig = CLIRig()
    let started = await rig.run("present", "on", "--json")
    #expect(started.exit == .success)
    #expect(await rig.config.load().meeting.presentingUntil == PauseWindow.indefinite)
    let report = try started.json()
    #expect(report["presenting"] as? Bool == true)
    #expect(report["presentingIndefinitely"] as? Bool == true)
    #expect(started.stdout.contains("\"mode\""))
    let off = await rig.run("present", "off")
    #expect(off.exit == .success)
    #expect(await rig.config.load().meeting.presentingUntil == nil)
    #expect(off.stdout.contains("Not presenting"))
  }

  @Test func presentOnForAWhileEndsThen() async throws {
    let rig = CLIRig()
    let result = await rig.run("present", "on", "--for", "90m", "--json")
    #expect(result.exit == .success)
    let expected = rig.clock.now().addingTimeInterval(5400)
    #expect(await rig.config.load().meeting.presentingUntil == expected)
    #expect(try result.json()["presentingIndefinitely"] as? Bool == false)
  }

  @Test func presentRejectsBadInput() async {
    let rig = CLIRig()
    #expect(await rig.run("present", "maybe").exit == .usage)
    #expect(await rig.run("present", "on", "--for", "soon").exit == .usage)
    #expect(await rig.run("present", "off", "--for", "1h").exit == .usage)
    #expect(await rig.config.load().meeting.presentingUntil == nil)
  }

  @Test func presentKeepsTheModeAndWorksWithoutTheApp() async {
    let rig = CLIRig(app: FakeApp(failure: .appUnavailable))
    _ = await rig.run("config", "meeting", "set", "--mode", "pause")
    #expect(await rig.run("present", "on", "--for", "1h").exit == .success)
    let meeting = await rig.config.load().meeting
    #expect(meeting.mode == .pause)
    #expect(meeting.isPresenting(at: rig.clock.now()))
  }

  // MARK: status

  private func appStatus(meeting: MeetingSummary?) -> Response {
    .success(
      id: "s",
      result: ResultPayload(
        status: StatusResult(
          connection: "connected", appVersion: Version.current,
          permission: PermissionSummary(usable: true), meeting: meeting)))
  }

  @Test func statusShowsTheMeetingTheAppDetected() async throws {
    let app = FakeApp()
    await app.reply(
      to: .status,
      with: appStatus(meeting: MeetingSummary(active: true, reason: "app", detail: "Zoom")))
    let rig = CLIRig(app: app)
    await rig.config.update { $0.meeting.mode = .pause }
    let json = try await rig.run("status", "--json").json()
    let meeting = try #require(json["meeting"] as? [String: Any])
    #expect(meeting["mode"] as? String == "pause")
    #expect(meeting["active"] as? Bool == true)
    #expect(meeting["reason"] as? String == "app")
    #expect(meeting["detail"] as? String == "Zoom")
    #expect(await rig.run("status").stdout.contains("Meeting:     in a meeting (Zoom)"))
  }

  @Test func statusFromAnOlderAppFallsBackToTheFile() async throws {
    let app = FakeApp()
    await app.reply(to: .status, with: appStatus(meeting: nil))
    let rig = CLIRig(app: app)
    await rig.config.update { $0.meeting.presentingUntil = PauseWindow.indefinite }
    let meeting = try #require(
      try await rig.run("status", "--json").json()["meeting"] as? [String: Any])
    #expect(meeting["active"] as? Bool == true)
    #expect(meeting["reason"] as? String == "presenting")
    #expect(meeting["presenting"] as? Bool == true)
  }

  @Test func withTheAppDownStatusKnowsTheModeAndTheOverrideOnly() async throws {
    let rig = CLIRig(app: FakeApp(failure: .appUnavailable))
    await rig.config.update { $0.meeting.mode = .pause }
    let json = try await rig.run("status", "--json").json()
    let meeting = try #require(json["meeting"] as? [String: Any])
    #expect(meeting["mode"] as? String == "pause")
    #expect(meeting["active"] as? Bool == false)
    #expect(meeting["reason"] is NSNull)
    #expect(await rig.run("status").stdout.contains("Meeting:     on, no meeting"))
  }
}
