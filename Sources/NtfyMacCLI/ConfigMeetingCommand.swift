import ArgumentParser
import Foundation
import NtfyCore

/// The meeting group as `config meeting` prints it.
struct MeetingReport: Encodable, Sendable {
  let mode: String
  let urgentBypass: Bool
  let presenting: Bool
  let presentingUntil: Date?
  let presentingIndefinitely: Bool

  init(_ meeting: MeetingSettings, now: Date) {
    mode = meeting.mode.rawValue
    urgentBypass = meeting.urgentBypass
    presenting = meeting.isPresenting(at: now)
    presentingUntil = presenting ? meeting.presentingUntil : nil
    presentingIndefinitely = presentingUntil.map(PauseWindow.isIndefinite) ?? false
  }

  var text: String {
    """
    Meetings: \(mode == MeetingMode.off.rawValue ? "off" : "pause notifications while a meeting is detected")
      Urgent bypass: \(urgentBypass ? "yes" : "no")
      Presenting:    \(presentingText)
    """
  }

  var presentingText: String {
    guard presenting, let presentingUntil else { return "no" }
    return presentingIndefinitely
      ? "yes, until: ntfy-mac present off" : "until \(MessageText.timestamp(presentingUntil))"
  }
}

struct ConfigMeetingCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "meeting", abstract: "Pause notifications automatically during video meetings.",
    discussion: """
      With the mode on, the app watches which apps use the microphone and whether a camera is
      running (Zoom, Teams, Webex, FaceTime, a Slack huddle, a browser call with the camera on)
      and holds banners and sounds back while a meeting is going on. Messages are stored and
      shown as one summary when it ends. Nothing is recorded and no macOS permission is needed:
      the app only learns that audio or a camera is in use, never what is said or shown. It
      cannot see a screen share by itself; `ntfy-mac present on` says so by hand.
      """,
    subcommands: [ConfigMeetingShow.self, ConfigMeetingSet.self, ConfigMeetingReset.self])

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await ConfigMeetingShow.show(environment, out)
  }
}

struct ConfigMeetingShow: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "show", abstract: "Show the meeting settings.")

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await Self.show(environment, out)
  }

  static func show(_ environment: CLIEnvironment, _ out: Output) async throws {
    let meeting = try await environment.config.load().meeting
    let report = MeetingReport(meeting, now: environment.clock.now())
    out.result(report, text: report.text)
  }
}

extension MeetingMode: ExpressibleByArgument {}

struct ConfigMeetingSet: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "set", abstract: "Change the meeting settings.",
    discussion: """
      Options you leave out keep their value. The defaults are mode off and urgent bypass on.

        ntfy-mac config meeting set --mode pause
        ntfy-mac config meeting set --no-urgent-bypass
      """)

  @Option(name: .long, help: "off, or pause to hold notifications during meetings.")
  var mode: MeetingMode?
  @Flag(name: .long, help: "Let priority 5 through.") var urgentBypass = false
  @Flag(name: .long, help: "Hold priority 5 back too.") var noUrgentBypass = false
  @OptionGroup var output: OutputOptions

  func validate() throws {
    guard !(urgentBypass && noUrgentBypass) else {
      throw ValidationError("Use either --urgent-bypass or --no-urgent-bypass, not both.")
    }
    guard mode != nil || urgentBypass || noUrgentBypass else {
      throw ValidationError("Give --mode, --urgent-bypass or --no-urgent-bypass.")
    }
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let mode = mode
    let changesBypass = urgentBypass || noUrgentBypass
    let bypass = urgentBypass
    try await environment.config.update { config in
      if let mode { config.meeting.mode = mode }
      if changesBypass { config.meeting.urgentBypass = bypass }
    }
    try await ConfigMeetingShow.show(environment, out)
  }
}

struct ConfigMeetingReset: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "reset", abstract: "Turn meeting detection off and restore the defaults.",
    discussion: "A running `present on` stays until `ntfy-mac present off`.")

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    try await environment.config.update { config in
      config.meeting = MeetingSettings(presentingUntil: config.meeting.presentingUntil)
    }
    try await ConfigMeetingShow.show(environment, out)
  }
}
