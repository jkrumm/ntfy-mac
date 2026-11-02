import Foundation
import Testing

@testable import NtfyCore

@Suite struct MeetingSettingsTests {
  private func config(_ json: String) throws -> Config {
    try #require(Config.parse(Data(json.utf8)))
  }

  @Test func anAbsentGroupIsOffWithTheBypassOn() throws {
    let meeting = try config("{}").meeting
    #expect(meeting == MeetingSettings(mode: .off, urgentBypass: true, presentingUntil: nil))
  }

  @Test func theGroupRoundTrips() throws {
    var original = Config()
    original.meeting = MeetingSettings(
      mode: .pause, urgentBypass: false,
      presentingUntil: Date(timeIntervalSince1970: 1_800_000_000))
    let data = try original.serialized()
    #expect(Config.parse(data)?.meeting == original.meeting)
  }

  @Test func defaultsAreNotWritten() throws {
    #expect(Config().object["meeting"] == nil)
    var config = Config()
    config.meeting.mode = .pause
    let object = try #require(config.object["meeting"]?.objectValue)
    #expect(Set(object.keys) == ["mode"])
  }

  @Test func wrongTypesAndUnknownModesReadAsDefaults() throws {
    let meeting = try config(
      #"{"meeting":{"mode":"always","urgentBypass":"no","presentingUntil":5}}"#
    ).meeting
    #expect(meeting == MeetingSettings())
    #expect(try config(#"{"meeting":"on"}"#).meeting == MeetingSettings())
  }

  @Test func theOverrideWinsAndWorksWithModeOff() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    var settings = MeetingSettings(mode: .off)
    #expect(settings.effectiveState(detected: .active(.app("Zoom")), at: now) == .inactive)
    settings.presentingUntil = now.addingTimeInterval(60)
    #expect(settings.effectiveState(detected: .inactive, at: now) == .active(.presenting))
    #expect(
      settings.effectiveState(detected: .inactive, at: now.addingTimeInterval(60)) == .inactive)
  }

  @Test func detectionCountsOnlyInPauseMode() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let detected = MeetingState.active(.app("Zoom"))
    #expect(MeetingSettings(mode: .pause).effectiveState(detected: detected, at: now) == detected)
    #expect(MeetingSettings(mode: .off).effectiveState(detected: detected, at: now) == .inactive)
  }

  @Test func unknownKeysOfTheGroupAreKnownToTheConfig() {
    #expect(Config.knownKeys.contains("meeting"))
  }
}
