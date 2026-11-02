import Foundation
import NtfyCore
import NtfyIPC

/// Tests the connection, then saves the URL to the config and the token to the Keychain.
struct ServerSetup {
  let environment: CLIEnvironment
  let out: Output

  struct Report: Encodable, Sendable {
    let url: String
    let topics: [String]
    /// Whether the app answered after the config was saved.
    let appRunning: Bool
  }

  /// - Throws: the server's `NtfyError` (unauthorized, unreachable, ...) before anything is saved.
  func connect(url: URL, token: String) async throws -> Report {
    let token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    out.note("Testing connection...")
    let source = environment.topicSource(url, token, false)
    let topics = try await source.subscribedTopics()
    try await environment.secrets.setToken(token)
    let address = url.absoluteString
    try await environment.config.update { config in
      config.url = address
      config.token = nil
    }
    return Report(url: address, topics: topics, appRunning: await startApp())
  }

  /// The app watches the config, so a running one picks the change up; a stopped one is started.
  /// Not being able to start it does not fail the setup.
  private func startApp() async -> Bool {
    do {
      _ = try await environment.app.send(
        Request(id: UUID().uuidString, command: .ping), launch: true)
      return true
    } catch {
      out.note("The ntfy-mac app is not running. Start it with: ntfy-mac start")
      return false
    }
  }
}

/// The interactive flow: ask, test, offer a retry.
struct SetupWizard {
  let setup: ServerSetup
  let prompter: any Prompting
  let out: Output

  func run() async throws -> ServerSetup.Report {
    out.note("ntfy-mac setup\nConfigure your ntfy server credentials.\n")
    while true {
      guard let rawURL = prompter.ask("ntfy server URL", default: nil), !rawURL.isEmpty else {
        throw CLIFailure.runtime("setup-cancelled", "Setup cancelled.")
      }
      let url: URL
      do {
        url = try ServerURL.parse(rawURL)
      } catch let failure as CLIFailure {
        out.note("\(failure.message)\n")
        continue
      }
      out.note("  Get your token at \(url.absoluteString)/account -> Access Tokens")
      guard let token = prompter.askSecret("Auth token"), !token.isEmpty else {
        out.note("Token is required.\n")
        continue
      }
      do {
        return try await setup.connect(url: url, token: token)
      } catch let error as NtfyError {
        out.note("Connection failed: \(error.cliMessage)\n")
        let retry = prompter.ask("Retry? (y/n)", default: "y")?.lowercased()
        guard retry == "y" || retry == "yes" else { throw error }
      }
    }
  }
}
