import ArgumentParser
import Foundation

/// The notification pause as the config file stores it (`pausedUntil`).
enum PauseWindow {
  /// "Until further notice" is stored as this far-future date.
  static let indefinite = Date(timeIntervalSince1970: 4_102_444_800)  // 2100-01-01T00:00:00Z

  static func isIndefinite(_ date: Date) -> Bool { date >= indefinite }
}

struct PauseReport: Encodable {
  let paused: Bool
  let until: Date?
  let indefinite: Bool

  init(until: Date?) {
    paused = until != nil
    self.until = until
    indefinite = until.map(PauseWindow.isIndefinite) ?? false
  }

  func text() -> String {
    guard let until else { return "Notifications are on." }
    if indefinite { return "Notifications are paused until you run: ntfy-mac resume" }
    return "Notifications are paused until \(MessageText.timestamp(until))."
  }
}

struct PauseCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "pause", abstract: "Hold notifications back for a while.",
    discussion: """
      Writes pausedUntil to the config file; the running app picks it up through its config
      watcher, so it need not be reachable. Held-back messages are stored and shown when the
      pause ends. Without --for or --until the pause lasts until `ntfy-mac resume`. Durations
      use s, m, h and d, alone or combined: 30m, 2h, 1d, 1h30m.
      """)

  @Option(name: .long, help: "Pause for this long, like 30m, 2h or 1d.") var `for`: String?
  @Option(name: .long, help: "Pause until this ISO 8601 time.") var until: String?
  @OptionGroup var output: OutputOptions

  func validate() throws {
    guard `for` == nil || until == nil else {
      throw ValidationError("Use either --for or --until, not both.")
    }
    if let `for` {
      guard let seconds = DurationParser.seconds(`for`) else {
        throw ValidationError("--for must look like 30m, 2h, 1d or 1h30m (got \(`for`)).")
      }
      guard Date().addingTimeInterval(seconds) < PauseWindow.indefinite else {
        throw ValidationError("--for is too long; omit it to pause until resume.")
      }
    }
    if let until {
      guard TimePoint.iso8601(until) != nil else {
        throw ValidationError("--until must be an ISO 8601 time (got \(until)).")
      }
    }
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let now = environment.clock.now()
    let target = try end(now: now)
    try await environment.config.update { $0.pausedUntil = target }
    let report = PauseReport(until: target)
    out.result(report, text: report.text())
  }

  private func end(now: Date) throws -> Date {
    if let `for`, let seconds = DurationParser.seconds(`for`) {
      return now.addingTimeInterval(seconds)
    }
    if let until, let date = TimePoint.iso8601(until) {
      guard date > now else { throw CLIFailure.usage("--until must be in the future.") }
      return date
    }
    return PauseWindow.indefinite
  }
}

struct ResumeCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "resume", abstract: "End a pause and show what was held back.",
    discussion: "Clears pausedUntil in the config file; the running app picks it up.")

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await environment.config.update { $0.pausedUntil = nil }
    let report = PauseReport(until: nil)
    out.result(report, text: report.text())
  }
}
