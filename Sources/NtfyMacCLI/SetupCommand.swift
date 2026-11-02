import ArgumentParser
import Foundation
import NtfyCore
import NtfyIPC

struct SetupCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "setup", abstract: "Connect ntfy-mac to your ntfy server.",
    discussion: "Without options, an interactive wizard asks for the URL and token (terminal only)."
  )

  @Option(name: .long, help: "The ntfy server URL.") var url: String?
  @Option(name: .long, help: "An access token for the server.") var token: String?
  @OptionGroup var output: OutputOptions

  static let loginItemHint = "Start ntfy-mac at login with: ntfy-mac login-item"

  func validate() throws {
    guard (url == nil) == (token == nil) else {
      throw ValidationError("--url and --token must both be provided.")
    }
    if let url {
      do {
        _ = try ServerURL.parse(url)
      } catch let failure as CLIFailure {
        throw ValidationError(failure.message)
      }
    }
    if let token, token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      throw ValidationError("--token must not be empty.")
    }
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let setup = ServerSetup(environment: environment, out: out)
    let report: ServerSetup.Report
    if let url, let token {
      report = try await setup.connect(url: ServerURL.parse(url), token: token)
    } else {
      guard environment.terminal.isInteractive else {
        throw CLIFailure.usage(
          "setup needs a terminal to ask questions. "
            + "Pass them instead: ntfy-mac setup --url <url> --token <token>")
      }
      report = try await SetupWizard(setup: setup, prompter: environment.prompter, out: out).run()
    }
    out.result(
      report,
      text: "Configured: \(report.url) (\(report.topics.count) topic(s))\n" + Self.loginItemHint)
  }
}
