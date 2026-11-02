import ArgumentParser
import Foundation
import NtfyPlatform

struct LogsCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "logs", abstract: "Show the app's log from the unified log.",
    discussion: "With --json every line is one JSON object (NDJSON).")

  @Flag(name: .long, help: "Only errors and faults.") var error = false
  @Flag(name: [.short, .long], help: "Keep streaming new lines.") var follow = false
  @Option(name: .long, help: "How far back to look, like 30m, 1h or 2d (default 1h).")
  var last: String?
  @OptionGroup var output: OutputOptions

  static let logTool = "/usr/bin/log"
  static let defaultWindow = "1h"

  func validate() throws {
    guard let last else { return }
    guard !follow else { throw ValidationError("--last cannot be combined with --follow.") }
    let unit = last.last.map(String.init)
    guard let unit, ["m", "h", "d"].contains(unit), Int(last.dropLast()) != nil else {
      throw ValidationError("--last must look like 30m, 1h or 2d (got \(last)).")
    }
  }

  /// The `log` arguments for this invocation.
  func arguments() -> [String] {
    var arguments = [follow ? "stream" : "show", "--predicate", Self.predicate(errorsOnly: error)]
    if follow {
      arguments += ["--level", "info"]
    } else {
      arguments += ["--info", "--last", last ?? Self.defaultWindow]
    }
    if output.json { arguments += ["--style", "ndjson"] }
    return arguments
  }

  static func predicate(errorsOnly: Bool) -> String {
    let subsystem = "subsystem == \"\(Log.subsystem)\""
    return errorsOnly
      ? subsystem + " AND (messageType == error OR messageType == fault)" : subsystem
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let status = try await environment.processes.run(Self.logTool, arguments(), output: .inherit)
    guard status == 0 else {
      throw CLIFailure.runtime("logs-failed", "log exited with status \(status).")
    }
  }
}
