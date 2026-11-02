import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyIPC
import NtfyTesting
import Testing

@Suite struct IPCMeetingStatusTests {
  @Test func statusReportsTheDetectedMeetingOnlyInPauseMode() async throws {
    let provider = ManualMeetingState(.active(.slackHuddle))
    let rig = HandlerRig(
      config: Config(meeting: MeetingSettings(mode: .pause)), meeting: provider)
    let result = try #require(
      await rig.send(Request(id: "1", command: .status)).result?.status?.meeting)
    #expect(result == MeetingSummary(active: true, reason: "huddle", detail: "Slack"))

    let off = HandlerRig(config: Config(), meeting: provider)
    let quiet = try #require(
      await off.send(Request(id: "1", command: .status)).result?.status?.meeting)
    #expect(quiet == MeetingSummary(active: false))
  }

  @Test func statusReportsTheOverride() async throws {
    let rig = HandlerRig(
      config: Config(meeting: MeetingSettings(presentingUntil: PauseWindow.indefinite)))
    let summary = try #require(
      await rig.send(Request(id: "1", command: .status)).result?.status?.meeting)
    #expect(
      summary == MeetingSummary(active: true, reason: "presenting", detail: nil, presenting: true))
  }

  @Test func theOldStatusShapeStillDecodes() throws {
    let json = Data(#"{"connection":"connected","appVersion":"2.0.0"}"#.utf8)
    let status = try JSONDecoder().decode(StatusResult.self, from: json)
    #expect(status.meeting == nil)
  }
}
