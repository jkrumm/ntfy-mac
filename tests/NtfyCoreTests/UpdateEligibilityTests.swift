import Testing

@testable import NtfyCore

@Suite struct UpdateEligibilityTests {
  // Obviously fake Team IDs.
  private static let team = "TEAM000001"
  private static let other = "TEAM000002"

  @Test(arguments: [
    (nil, nil, TeamPin.Verdict.unsigned),
    (nil, "", .unsigned),
    ("TEAM000001", nil, .unsigned),
    (nil, "TEAM000001", .record("TEAM000001")),
    ("", "TEAM000001", .record("TEAM000001")),
    ("TEAM000001", "TEAM000001", .matches),
    ("TEAM000001", "TEAM000002", .mismatch),
  ])
  func pinTable(recorded: String?, current: String?, expected: TeamPin.Verdict) {
    #expect(TeamPin.evaluate(recorded: recorded, current: current) == expected)
  }

  @Test(arguments: [
    ("/opt/homebrew/Cellar/ntfy-mac/2.0.0/NtfyMac.app/Contents/MacOS/ntfy-mac", "homebrew"),
    ("/usr/local/opt/ntfy-mac/NtfyMac.app/Contents/MacOS/ntfy-mac", "homebrew"),
    ("/Applications/NtfyMac.app/Contents/MacOS/ntfy-mac", "direct"),
    ("/Users/me/Applications/NtfyMac.app/Contents/MacOS/NtfyMac", "direct"),
    ("/opt/homebrew/Cellar/other/1.0/bin/tool", "direct"),
  ])
  func channelDetection(path: String, expected: String) {
    #expect(InstallChannel.detect(executablePath: path).rawValue == expected)
  }

  private func evaluate(
    channel: InstallChannel = .direct, disabled: Bool = false,
    signing: SigningInfo = SigningInfo(teamID: team, hardenedRuntime: true, developerID: true),
    recorded: String? = nil
  ) -> UpdateEligibility {
    .evaluate(channel: channel, disabled: disabled, signing: signing, recordedTeam: recorded)
  }

  @Test func aSignedDirectCopyUpdatesAndRecordsItsTeamOnTheFirstRun() {
    let first = evaluate()
    #expect(first.reason == nil)
    #expect(first.teamToRecord == Self.team)
    let later = evaluate(recorded: Self.team)
    #expect(later.reason == nil && later.teamToRecord == nil)
  }

  @Test func aHomebrewCopyNeverUpdatesItself() {
    #expect(evaluate(channel: .homebrew).reason == .homebrew)
    #expect(evaluate(channel: .homebrew, disabled: true).reason == .homebrew)
  }

  @Test func theEnvironmentSwitchDisables() {
    #expect(evaluate(disabled: true).reason == .disabled)
  }

  @Test(arguments: [
    SigningInfo.unsigned,
    SigningInfo(teamID: "TEAM000001", hardenedRuntime: true, developerID: false),
    SigningInfo(teamID: nil, hardenedRuntime: false, developerID: true),
  ])
  func aBuildWithoutADeveloperIDIsUnsignedAndNeverRecorded(signing: SigningInfo) {
    let result = evaluate(signing: signing)
    #expect(result.reason == .unsigned)
    #expect(result.teamToRecord == nil)
  }

  @Test func anotherTeamIsAMismatch() {
    let result = evaluate(recorded: Self.other)
    #expect(result.reason == .teamMismatch)
    #expect(result.pin == .mismatch)
    #expect(result.teamToRecord == nil)
  }

  @Test func reasonsHaveStableWireNames() {
    #expect(
      UpdateUnavailableReason.allCases.map(\.rawValue)
        == ["homebrew", "unsigned", "disabled", "team-mismatch"])
  }
}
