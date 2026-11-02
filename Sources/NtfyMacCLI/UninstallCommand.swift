import ArgumentParser
import Foundation

struct UninstallCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "uninstall", abstract: "Remove ntfy-mac's config, history, state and token.",
    discussion: "The app itself is not deleted; the output says how to remove it.")

  @Flag(name: .long, help: "Do not ask for confirmation (required without a terminal).")
  var yes = false
  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let uninstaller = Uninstaller(paths: environment.paths, secrets: environment.secrets)
    if !yes {
      guard environment.terminal.isInteractive else {
        throw CLIFailure.usage("Refusing to delete without confirmation. Pass --yes.")
      }
      out.note("This removes:")
      for item in uninstaller.items { out.note("  \(item.label): \(item.url.path)") }
      out.note("  the access token in the Keychain")
      let answer = environment.prompter.ask("Continue? (y/N)", default: "n")?.lowercased()
      guard answer == "y" || answer == "yes" else {
        throw CLIFailure.runtime("cancelled", "Cancelled; nothing was removed.")
      }
    }
    let report = await uninstaller.run()
    out.result(report, text: report.text())
    if !report.failed.isEmpty { throw ExitRequest(exit: .runtime) }
  }
}
