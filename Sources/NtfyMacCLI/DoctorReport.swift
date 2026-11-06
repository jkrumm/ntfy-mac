import Foundation
import NtfyCore

struct DoctorCheck: Encodable, Sendable {
  enum Status: String, Encodable, Sendable {
    case passed = "ok"
    case warn, fail, skipped
  }

  let name: String
  let status: Status
  let message: String
  let detail: String?
  /// The exit code a failing check asks for; not part of the report.
  let exit: ProcessExit

  private enum CodingKeys: String, CodingKey { case name, status, message, detail }

  init(
    _ name: String, _ status: Status, _ message: String, detail: String? = nil,
    exit: ProcessExit = .runtime
  ) {
    self.name = name
    self.status = status
    self.message = message
    self.detail = detail
    self.exit = exit
  }

  static func failure(_ name: String, _ error: NtfyError, _ message: String) -> DoctorCheck {
    DoctorCheck(
      name, .fail, message, detail: error.cliMessage, exit: ProcessExit(error: error))
  }
}

struct DoctorReport: Encodable, Sendable {
  let version: String
  let installChannel: InstallChannel
  let healthy: Bool
  private enum CodingKeys: String, CodingKey {
    case version, installChannel, checks
    case healthy = "ok"
  }
  let checks: [DoctorCheck]

  init(installChannel: InstallChannel, checks: [DoctorCheck]) {
    version = Version.current
    self.installChannel = installChannel
    self.checks = checks
    healthy = !checks.contains { $0.status == .fail }
  }

  /// The most specific code among the failures: auth, unreachable or app before plain runtime.
  var exit: ProcessExit {
    let failing = checks.filter { $0.status == .fail }.map(\.exit)
    return failing.first { $0 != .runtime } ?? (failing.isEmpty ? .success : .runtime)
  }

  func text() -> String {
    var lines = ["ntfy-mac doctor (\(version))", ""]
    let icons: [DoctorCheck.Status: String] = [.passed: "✓", .warn: "!", .fail: "✗", .skipped: "-"]
    for check in checks {
      let name = check.name.padding(toLength: 15, withPad: " ", startingAt: 0)
      lines.append("  \(icons[check.status] ?? "?") \(name) \(check.message)")
      if let detail = check.detail { lines.append(String(repeating: " ", count: 19) + detail) }
    }
    let failures = checks.filter { $0.status == .fail }.count
    let warnings = checks.filter { $0.status == .warn }.count
    lines.append("")
    if failures > 0 {
      lines.append("\(failures) issue(s) found. Fix them and run again.")
    } else if warnings > 0 {
      lines.append("All good, \(warnings) suggestion(s).")
    } else {
      lines.append("Everything looks good.")
    }
    return lines.joined(separator: "\n")
  }
}
