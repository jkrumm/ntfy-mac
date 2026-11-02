import Foundation
import NtfyCore
import Testing

@testable import NtfyMacCLI

@Suite struct OperationsCommandTests {
  // MARK: update

  @Test func aBrewInstallRunsBrewUpgrade() async {
    var rig = CLIRig()
    rig.executablePath = "/opt/homebrew/Cellar/ntfy-mac/2.0.0/NtfyMac.app/Contents/MacOS/ntfy-mac"
    let result = await rig.run("update")
    #expect(result.exit == .success)
    let runs = await rig.processes.runs
    #expect(
      runs == [
        .init(executable: "/usr/bin/env", arguments: ["brew", "upgrade", "jkrumm/tap/ntfy-mac"])
      ])
  }

  @Test func aFailedBrewUpgradeIsAnError() async {
    var rig = CLIRig(processes: FakeProcesses(status: 1))
    rig.executablePath = "/opt/homebrew/Cellar/ntfy-mac/2.0.0/bin/ntfy-mac"
    let result = await rig.run("update")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("brew upgrade failed"))
  }

  @Test func anotherInstallGetsAnActionableError() async {
    let rig = CLIRig()
    let result = await rig.run("update")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("Rerun the installer"))
    #expect(await rig.processes.runs.isEmpty)
  }

  @Test func checkReportsANewerRelease() async throws {
    var rig = CLIRig()
    rig.releases = FakeReleases(tag: "v9.0.0")
    let result = await rig.run("update", "--check", "--json")
    #expect(result.exit == .success)
    #expect(try result.json()["updateAvailable"] as? Bool == true)
    #expect(try result.json()["latest"] as? String == "9.0.0")
    #expect(await rig.processes.runs.isEmpty)
  }

  @Test func checkReportsUpToDate() async {
    var rig = CLIRig()
    rig.releases = FakeReleases(tag: "v\(Version.current)")
    #expect(await rig.run("update", "--check").stdout.contains("Up to date"))
  }

  @Test func checkFailsWithSevenWhenGitHubIsUnreachable() async {
    var rig = CLIRig()
    rig.releases = FakeReleases(failure: .serverUnreachable)
    #expect(await rig.run("update", "--check").exit == .serverUnreachable)
  }

  @Test(arguments: [
    ("2.0.1", "2.0.0", true), ("v2.1.0", "2.0.9", true), ("2.0.0", "2.0.0-dev", true),
    ("2.0.0", "2.0.0", false), ("1.9.9", "2.0.0", false), ("10.0.0", "9.9.9", true),
    ("junk", "2.0.0", false),
  ])
  func versionComparison(latest: String, current: String, newer: Bool) {
    #expect(SemanticVersion.isNewer(latest, than: current) == newer)
  }

  // MARK: logs

  @Test func logsShowTheAppSubsystem() async {
    let rig = CLIRig()
    let result = await rig.run("logs")
    #expect(result.exit == .success)
    #expect(
      await rig.processes.runs == [
        .init(
          executable: "/usr/bin/log",
          arguments: [
            "show", "--predicate", "subsystem == \"com.jkrumm.ntfy-mac\"", "--info", "--last", "1h",
          ])
      ])
  }

  @Test func logsErrorFiltersAndJSONSelectsNDJSON() async {
    let rig = CLIRig()
    _ = await rig.run("logs", "--error", "--last", "30m", "--json")
    let arguments = await rig.processes.runs.first?.arguments ?? []
    #expect(
      arguments.contains(
        "subsystem == \"com.jkrumm.ntfy-mac\" AND (messageType == error OR messageType == fault)"))
    #expect(arguments.suffix(2) == ["--style", "ndjson"])
    #expect(arguments.contains("30m"))
  }

  @Test func followStreams() async {
    let rig = CLIRig()
    _ = await rig.run("logs", "--follow")
    #expect(await rig.processes.runs.first?.arguments.first == "stream")
  }

  @Test(arguments: [["--last", "soon"], ["--last", "5"], ["--follow", "--last", "1h"]])
  func badWindowsAreUsageErrors(extra: [String]) async {
    #expect(await CLIRig().run(["logs"] + extra).exit == .usage)
  }

  // MARK: sounds

  @Test func soundsPlayEachMatchingSound() async {
    let rig = CLIRig()
    let result = await rig.run("sounds", "PO")
    #expect(result.exit == .success)
    #expect(result.stdout == "Playing: Pop\n")
    let runs = await rig.processes.runs
    #expect(runs.map(\.executable) == ["/usr/bin/afplay"])
    #expect(runs.first?.arguments.first?.hasSuffix("sounds/Pop.aiff") == true)
  }

  @Test func soundsJSONListsNamesWithoutPlaying() async throws {
    let rig = CLIRig()
    let result = await rig.run("sounds", "--json")
    #expect(try result.json()["sounds"] as? [String] == ["Ping", "Pop", "Sosumi", "Tink"])
    #expect(await rig.processes.runs.isEmpty)
  }

  @Test func soundsWithoutAMatchFails() async {
    let result = await CLIRig().run("sounds", "zzz")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("No sound matching"))
  }

  // MARK: start and version

  @Test func startDoesNothingWhenTheAppRuns() async {
    let rig = CLIRig()
    let result = await rig.run("start")
    #expect(result.stdout.contains("already running"))
    #expect(await rig.app.calls.map(\.launch) == [false])
  }

  @Test func startLaunchesAnAppThatIsDown() async {
    // The first ping (no launch) finds nothing; the second may launch.
    let rig = CLIRig(app: FakeApp(failure: .appUnavailable))
    let result = await rig.run("start")
    #expect(result.exit == .appUnavailable)
    #expect(await rig.app.calls.map(\.launch) == [false, true])
  }

  @Test func versionPrintsTheBanner() async throws {
    let rig = CLIRig()
    #expect(await rig.run("version").stdout == "ntfy-mac \(Version.current)\n")
    #expect(try await rig.run("version", "--json").json()["version"] as? String == Version.current)
  }
}
