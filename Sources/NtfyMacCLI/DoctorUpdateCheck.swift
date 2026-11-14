import Foundation
import NtfyCore

extension DoctorChecks {
  /// Who updates this copy, and whether the app's updater can: install channel, signature, the
  /// pinned Team ID. Reads only; the app records the pin.
  func updateCheck() -> DoctorCheck {
    let recorded = try? environment.teamPins.recorded()
    let eligibility = UpdateEligibility.evaluate(
      channel: InstallChannel.detect(executablePath: environment.executablePath),
      disabled: environment.variables["NTFY_MAC_NO_SELF_UPDATE"] == "1",
      signing: environment.signing.inspect(), recordedTeam: recorded)
    let signing = eligibility.signing
    let detail = [
      "Channel: \(eligibility.channel.rawValue)",
      "Developer ID: \(signing.developerID ? "yes" : "no")",
      "Hardened runtime: \(signing.hardenedRuntime ? "yes" : "no")",
      "Team pin: \(Self.pinText(eligibility.pin))",
    ].joined(separator: ", ")
    switch eligibility.reason {
    case nil:
      return DoctorCheck("update", .passed, "Updates through the app (Sparkle)", detail: detail)
    case .homebrew?:
      return DoctorCheck(
        "update", .passed,
        "Old Homebrew formula copy: run brew update, then brew uninstall --formula ntfy-mac",
        detail: detail)
    case .disabled?:
      return DoctorCheck(
        "update", .passed, "Self-update is off (NTFY_MAC_NO_SELF_UPDATE=1)", detail: detail)
    case .unsigned?:
      return DoctorCheck(
        "update", .passed, "No self-update: not signed with a Developer ID (a development build)",
        detail: detail)
    case .teamMismatch?:
      return DoctorCheck(
        "update", .warn, "Updates are off: signed by a different team than the first signed run",
        detail: detail)
    }
  }

  private static func pinText(_ pin: TeamPin.Verdict) -> String {
    switch pin {
    case .matches: "matches"
    case .record: "not recorded yet"
    case .mismatch: "MISMATCH"
    case .unsigned: "none"
    }
  }
}
