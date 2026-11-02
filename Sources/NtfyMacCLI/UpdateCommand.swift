import ArgumentParser
import Foundation
import NtfyCore

struct UpdateCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "update",
    abstract: "Update ntfy-mac to the latest release (Homebrew or a verified in-place download).")

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
    let from: String
    // The JSON key is `to`.
    // swiftlint:disable:next identifier_name
    let to: String?
    let updated: Bool
    let restarted: Bool
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
      try await installDirect(environment, out)
      return
    }
    out.note("Upgrading via Homebrew...")
    let status = try await environment.processes.run(
      "/usr/bin/env", ["brew", "upgrade", "jkrumm/tap/ntfy-mac"], output: .stderr)
    guard status == 0 else {
      throw CLIFailure.runtime("update-failed", "brew upgrade failed (exit status \(status)).")
    }
    out.result(
      UpdateReport(
        method: method, from: Version.current, to: nil, updated: true, restarted: false),
      text: "Done. Quit and reopen the ntfy-mac app to run the new version.")
  }

  /// The curl / manual install: a verified in-place replacement of `NtfyMac.app`.
  private func installDirect(_ environment: CLIEnvironment, _ out: Output) async throws {
    guard environment.variables["NTFY_MAC_NO_SELF_UPDATE"] != "1" else {
      throw CLIFailure.runtime(
        "update-disabled",
        "Self-update is disabled (NTFY_MAC_NO_SELF_UPDATE=1). Unset it, or update with your "
          + "package manager or by rerunning the installer.")
    }
    let executable = URL(fileURLWithPath: environment.executablePath).resolvingSymlinksInPath()
    guard let bundle = AppBundle.enclosing(of: executable) else {
      throw CLIFailure.runtime(
        "update-unsupported",
        "This ntfy-mac does not run from an NtfyMac.app (a development build), so it cannot "
          + "update itself. Install a release, or use 'ntfy-mac update --check'.")
    }
    let parent = bundle.deletingLastPathComponent()
    guard FileManager.default.isWritableFile(atPath: parent.path) else {
      throw CLIFailure.runtime(
        "update-not-writable",
        "Cannot update: \(parent.path) is not writable. Rerun the installer, or update "
          + "with the permissions to write there.")
    }
    let release = try await environment.releases.latest()
    let current = Version.current
    guard SemanticVersion.isNewer(release.tag, than: current) else {
      out.result(
        UpdateReport(
          method: .app, from: current, to: current, updated: false, restarted: false),
        text: "Up to date (\(current))")
      return
    }
    let restarted = try await SelfUpdater(ports: environment.update, bundle: bundle)
      .install(release, out)
    out.result(
      UpdateReport(
        method: .app, from: current, to: release.version, updated: true, restarted: restarted),
      text: restarted
        ? "Updated to \(release.version) and restarted the app."
        : "Updated to \(release.version).")
  }
}
