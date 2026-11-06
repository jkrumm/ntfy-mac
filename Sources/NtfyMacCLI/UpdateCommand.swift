import ArgumentParser
import Foundation
import NtfyCore
import NtfyIPC

struct UpdateCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "update",
    abstract: "Update ntfy-mac to the latest release (Homebrew, or the app's own updater).",
    discussion: """
      A Homebrew copy runs brew upgrade jkrumm/tap/ntfy-mac. Any other copy asks the running
      app (started if needed) to update itself: --check only looks, without any window; without
      it the app opens its own update prompt and the command returns at once. A development
      build, one signed by another team than the first signed install, and NTFY_MAC_NO_SELF_UPDATE=1
      all leave updating off; the command then says why and exits 0. An app from before this
      command exists answers with the error code app-outdated.
      """)

  @Flag(name: .long, help: "Only report whether a newer release exists; install nothing.")
  var check = false
  @OptionGroup var output: OutputOptions

  private struct Report: Encodable {
    let channel: String
    let current: String
    let latest: String?
    let updateAvailable: Bool
    /// Why updating is not possible: `homebrew`, `unsigned`, `disabled` or `team-mismatch`.
    let reason: String?
    /// The app was asked to run its update flow.
    let started: Bool
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let channel = InstallChannel.detect(executablePath: environment.executablePath)
    if channel == .homebrew {
      try await (check ? checkHomebrew(environment, out) : upgradeHomebrew(environment, out))
    } else {
      try await updateDirect(environment, out)
    }
  }

  // MARK: Homebrew

  private func checkHomebrew(_ environment: CLIEnvironment, _ out: Output) async throws {
    let release = try await environment.releases.latest()
    let current = Version.current
    let newer = SemanticVersion.isNewer(release.version, than: current)
    out.result(
      Report(
        channel: InstallChannel.homebrew.rawValue, current: current, latest: release.version,
        updateAvailable: newer, reason: nil, started: false),
      text: newer
        ? "Update available: \(release.version) (current: \(current)). Run: ntfy-mac update"
        : "Up to date (\(current))")
  }

  private func upgradeHomebrew(_ environment: CLIEnvironment, _ out: Output) async throws {
    out.note("Upgrading via Homebrew...")
    let status = try await environment.processes.run(
      "/usr/bin/env", ["brew", "upgrade", "jkrumm/tap/ntfy-mac"], output: .stderr)
    guard status == 0 else {
      throw CLIFailure.runtime("update-failed", "brew upgrade failed (exit status \(status)).")
    }
    out.result(
      Report(
        channel: InstallChannel.homebrew.rawValue, current: Version.current, latest: nil,
        updateAvailable: false, reason: nil, started: false),
      text: "Done. Quit and reopen the ntfy-mac app to run the new version.")
  }

  // MARK: Direct

  /// The app does the work (Sparkle lives there); this only asks and reports.
  private func updateDirect(_ environment: CLIEnvironment, _ out: Output) async throws {
    guard environment.variables["NTFY_MAC_NO_SELF_UPDATE"] != "1" else {
      report(
        UpdateStatus(channel: .direct, reason: .disabled), started: false, out)
      return
    }
    let request = Request(
      id: UUID().uuidString, command: .update, update: UpdatePayload(check: check))
    let response = try await environment.app.send(request, launch: true)
    if response.status == .error, response.code == .badRequest,
      response.message == IPC.invalidFrameMessage
    {
      throw CLIFailure.runtime(
        "app-outdated",
        "The running ntfy-mac app is too old to update itself. Quit it and run: ntfy-mac start")
    }
    guard let payload = try response.requireSuccess()?.update else {
      throw CLIFailure.runtime("invalid-response", "The app sent no update status.")
    }
    report(
      UpdateStatus(
        channel: InstallChannel(rawValue: payload.channel) ?? .direct,
        currentVersion: payload.currentVersion, latestVersion: payload.latestVersion,
        updateAvailable: payload.updateAvailable,
        reason: payload.reason.flatMap(UpdateUnavailableReason.init(rawValue:))),
      started: !check && payload.reason == nil, out)
  }

  private func report(_ status: UpdateStatus, started: Bool, _ out: Output) {
    let current = status.currentVersion
    let text: String
    if let reason = status.reason {
      text = Self.explanation(of: reason)
    } else if started {
      text = "Asked the app to update; follow the prompt in the app (current: \(current))."
    } else if status.updateAvailable {
      let latest = status.latestVersion.map { " \($0)" } ?? ""
      text = "Update available:\(latest) (current: \(current)). Run: ntfy-mac update"
    } else {
      text = "Up to date (\(current))"
    }
    out.result(
      Report(
        channel: status.channel.rawValue, current: current, latest: status.latestVersion,
        updateAvailable: status.updateAvailable, reason: status.reason?.rawValue,
        started: started),
      text: text)
  }

  private static func explanation(of reason: UpdateUnavailableReason) -> String {
    switch reason {
    case .homebrew:
      "This copy is managed by Homebrew. Update it with: brew upgrade jkrumm/tap/ntfy-mac"
    case .unsigned:
      "This build is not signed with a Developer ID (a development build), so it cannot "
        + "update itself. Install a release."
    case .disabled:
      "Self-update is turned off (NTFY_MAC_NO_SELF_UPDATE=1). Unset it to update."
    case .teamMismatch:
      "This build is signed by a different team than the first signed install, so it will "
        + "not update itself. Reinstall from the official release."
    }
  }
}
