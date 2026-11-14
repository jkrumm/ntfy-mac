import Foundation
import NtfyCore

extension DoctorChecks {
  /// Whether this copy's signature carries the time-sensitive entitlement, so priorities 4 and 5
  /// can break through Focus. Only a Developer ID build with an embedded provisioning profile has
  /// it; every other build downgrades to the active level, which is expected, not a fault.
  func timeSensitiveCheck() -> DoctorCheck {
    let signing = environment.signing.inspect()
    if signing.entitlements.contains(.timeSensitiveNotifications) {
      return DoctorCheck("time-sensitive", .passed, "Time-sensitive notifications available")
    }
    if signing.developerID {
      return DoctorCheck(
        "time-sensitive", .warn,
        "Developer ID build without the time-sensitive entitlement",
        detail: "Urgent messages arrive as active notifications and may not break through Focus")
    }
    return DoctorCheck(
      "time-sensitive", .passed, "Not available in this build (not signed with a Developer ID)",
      detail: "Urgent messages use the active level")
  }
}
