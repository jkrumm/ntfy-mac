import ArgumentParser
import Foundation
import NtfyCore

enum PresentChoice: String, CaseIterable, ExpressibleByArgument {
  case enable = "on"
  case disable = "off"
}

struct PresentCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "present", abstract: "Say you are presenting: hold notifications back.",
    discussion: """
      The app cannot tell that you share your screen, so this is the manual switch. `present on`
      holds banners and sounds back like a detected meeting (priority 5 still gets through
      unless the urgent bypass is off, see `config meeting`), whatever the meeting mode is.
      Without --for it lasts until `ntfy-mac present off`. Held messages are stored and shown
      as one summary afterwards. Writes meeting.presentingUntil to the config file; the running
      app picks it up through its config watcher, so it need not be reachable. Durations use
      s, m, h and d, alone or combined: 30m, 2h, 1h30m.

      macOS also hides banners by itself while the display is shared or mirrored, if System
      Settings > Notifications > "Allow notifications when mirroring or sharing the display"
      is off.
      """)

  @Argument(help: "on or off.") var state: PresentChoice
  @Option(name: .long, help: "With on: present for this long, like 30m, 2h or 1h30m.")
  var `for`: String?
  @OptionGroup var output: OutputOptions

  func validate() throws {
    guard let `for` else { return }
    guard state == .enable else { throw ValidationError("--for only goes with `present on`.") }
    guard DurationParser.seconds(`for`) != nil else {
      throw ValidationError("--for must look like 30m, 2h or 1h30m (got \(`for`)).")
    }
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let now = environment.clock.now()
    let until = try end(now: now)
    try await environment.config.update { $0.meeting.presentingUntil = until }
    let report = MeetingReport(try await environment.config.load().meeting, now: now)
    out.result(report, text: text(report))
  }

  private func end(now: Date) throws -> Date? {
    guard state == .enable else { return nil }
    guard let `for`, let seconds = DurationParser.seconds(`for`) else {
      return PauseWindow.indefinite
    }
    let date = now.addingTimeInterval(seconds)
    guard date < PauseWindow.indefinite else {
      throw CLIFailure.usage("--for is too long; omit it to present until `present off`.")
    }
    return date
  }

  private func text(_ report: MeetingReport) -> String {
    report.presenting
      ? "Presenting: notifications are held back (\(report.presentingText))."
      : "Not presenting: notifications are on."
  }
}
