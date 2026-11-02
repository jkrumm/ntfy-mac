import ArgumentParser
import NtfyCore

/// The quiet-hours schedule as `config quiet-hours` prints it.
struct QuietHoursReport: Encodable, Sendable {
  let enabled: Bool
  let start: String
  let end: String
  let urgentBypass: Bool
  let digest: Bool

  init(_ quiet: QuietHours) {
    enabled = quiet.enabled
    start = quiet.start.description
    end = quiet.end.description
    urgentBypass = quiet.urgentBypass
    digest = quiet.digest
  }

  var text: String {
    let state = enabled ? "on" : "off"
    return """
      Quiet hours: \(state)
        Window:        \(start) to \(end)
        Urgent bypass: \(urgentBypass ? "yes" : "no")
        Digest:        \(digest ? "yes" : "no")
      """
  }
}

struct ConfigQuietHoursCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "quiet-hours", abstract: "Hold notifications back during a daily window.",
    discussion: """
      Messages that arrive inside the window are stored and not notified. Priority 5 can bypass
      the window, and a digest can summarise what was held when the window ends.
      """,
    subcommands: [ConfigQuietHoursShow.self, ConfigQuietHoursSet.self, ConfigQuietHoursOff.self])

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await ConfigQuietHoursShow.show(environment, out)
  }
}

struct ConfigQuietHoursShow: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "show", abstract: "Show the quiet-hours schedule.")

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await Self.show(environment, out)
  }

  static func show(_ environment: CLIEnvironment, _ out: Output) async throws {
    let report = QuietHoursReport(try await environment.config.load().quietHours)
    out.result(report, text: report.text)
  }
}

/// A flag pair's answer; nil means neither was given.
private enum Choice: Sendable { case enabled, disabled }

struct ConfigQuietHoursSet: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "set", abstract: "Change the quiet-hours schedule and turn it on.",
    discussion: """
      Times are local, HH:mm (24 hours). The window may cross midnight. Options you leave out
      keep their value; the defaults are 22:00 to 07:00 with urgent bypass and digest on.

        ntfy-mac config quiet-hours set --start 22:00 --end 07:00
        ntfy-mac config quiet-hours set --no-urgent-bypass --no-digest
      """)

  @Option(name: .long, help: "Start of the window, HH:mm.") var start: String?
  @Option(name: .long, help: "End of the window, HH:mm (exclusive).") var end: String?
  @Flag(name: .long, help: "Let priority 5 through.") var urgentBypass = false
  @Flag(name: .long, help: "Hold priority 5 back too.") var noUrgentBypass = false
  @Flag(name: .long, help: "Summarise what was held when the window ends.") var digest = false
  @Flag(name: .long, help: "Show what was held one by one when the window ends.")
  var noDigest = false
  @OptionGroup var output: OutputOptions

  func validate() throws {
    guard !(urgentBypass && noUrgentBypass) else {
      throw ValidationError("Use either --urgent-bypass or --no-urgent-bypass, not both.")
    }
    guard !(digest && noDigest) else {
      throw ValidationError("Use either --digest or --no-digest, not both.")
    }
    _ = try parsed(start, "--start")
    _ = try parsed(end, "--end")
  }

  private func parsed(_ text: String?, _ name: String) throws -> ClockTime? {
    guard let text else { return nil }
    guard let time = ClockTime(text) else {
      throw ValidationError("\(name) must be a time like 22:00 or 07:30 (got \(text)).")
    }
    return time
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let start = try parsed(start, "--start")
    let end = try parsed(end, "--end")
    let bypass: Choice? = urgentBypass ? .enabled : noUrgentBypass ? .disabled : nil
    let digest: Choice? = digest ? .enabled : noDigest ? .disabled : nil
    let current = try await environment.config.load().quietHours
    guard (start ?? current.start) != (end ?? current.end) else {
      throw CLIFailure.usage("The window must have different start and end times.")
    }
    try await environment.config.update { config in
      config.quietHours.enabled = true
      if let start { config.quietHours.start = start }
      if let end { config.quietHours.end = end }
      if let bypass { config.quietHours.urgentBypass = bypass == .enabled }
      if let digest { config.quietHours.digest = digest == .enabled }
    }
    let report = QuietHoursReport(try await environment.config.load().quietHours)
    out.result(report, text: report.text)
  }
}

struct ConfigQuietHoursOff: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "off", abstract: "Turn quiet hours off and keep the times.")

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await environment.config.update { $0.quietHours.enabled = false }
    let report = QuietHoursReport(try await environment.config.load().quietHours)
    out.result(report, text: report.text)
  }
}
