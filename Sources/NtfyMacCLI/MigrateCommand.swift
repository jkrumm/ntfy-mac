import ArgumentParser
import Foundation
import NtfyCore

struct MigrateCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "migrate", abstract: "Remove the leftovers of a 1.x install.",
    discussion: """
      Stops and removes the 1.x LaunchAgent or brew service, the daemon, the ntfy-notify helper app \
      and its Launch Services entries, the old binary and logs. config.json and state.json stay. \
      The app does this itself on launch; run it by hand when doctor reports leftovers.
      """)

  @Flag(name: .long, help: "List what would be removed and change nothing.")
  var dryRun = false
  @OptionGroup var output: OutputOptions

  private struct Result: Encodable {
    let dryRun: Bool
    let found: [String]
    let removed: [String]
    let failed: [String]

    func text() -> String {
      var lines: [String] = []
      if dryRun {
        lines = found.map { "Would remove \($0)" }
      } else {
        lines = removed.map { "Removed \($0)" } + failed.map { "Failed: \($0)" }
      }
      if lines.isEmpty { lines = ["No 1.x leftovers found."] }
      return lines.joined(separator: "\n")
    }
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let report =
      dryRun ? await environment.legacy.detect() : await environment.legacy.run()
    let result = Result(
      dryRun: dryRun, found: report.found, removed: report.removed, failed: report.failed)
    out.result(result, text: result.text())
    if !report.failed.isEmpty { throw ExitRequest(exit: .runtime) }
  }
}
