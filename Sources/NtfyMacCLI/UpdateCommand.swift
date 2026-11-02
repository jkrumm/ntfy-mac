import ArgumentParser
import NtfyCore

struct UpdateCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "update",
    abstract: "Update ntfy-mac (Homebrew installs) or check for a newer release.")

  @Flag(name: .long, help: "Only report whether a newer release exists; install nothing.")
  var check = false
  @OptionGroup var output: OutputOptions

  private struct CheckReport: Encodable {
    let current: String
    let latest: String
    let updateAvailable: Bool
  }

  private struct UpdateReport: Encodable {
    let method: InstallMethod
    let updated: Bool
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    if check {
      try await checkForUpdate(environment, out)
    } else {
      try await upgrade(environment, out)
    }
  }

  private func checkForUpdate(_ environment: CLIEnvironment, _ out: Output) async throws {
    let tag = try await environment.releases.latestTag()
    let current = Version.current
    let newer = SemanticVersion.isNewer(tag, than: current)
    let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    out.result(
      CheckReport(current: current, latest: latest, updateAvailable: newer),
      text: newer
        ? "Update available: \(latest) (current: \(current)). Run: ntfy-mac update"
        : "Up to date (\(current))")
  }

  private func upgrade(_ environment: CLIEnvironment, _ out: Output) async throws {
    let method = InstallMethod.detect(executablePath: environment.executablePath)
    guard method == .brew else {
      throw CLIFailure.runtime(
        "update-unsupported",
        "This copy was not installed with Homebrew, so it cannot update itself yet. "
          + "Rerun the installer to get the latest release; a verified updater is planned. "
          + "Use 'ntfy-mac update --check' to see whether one exists.")
    }
    out.note("Upgrading via Homebrew...")
    let status = try await environment.processes.run(
      "/usr/bin/env", ["brew", "upgrade", "jkrumm/tap/ntfy-mac"], output: .stderr)
    guard status == 0 else {
      throw CLIFailure.runtime("update-failed", "brew upgrade failed (exit status \(status)).")
    }
    out.result(
      UpdateReport(method: method, updated: true),
      text: "Done. Quit and reopen the ntfy-mac app to run the new version.")
  }
}
