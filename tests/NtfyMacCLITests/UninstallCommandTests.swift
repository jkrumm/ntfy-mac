import Foundation
import NtfyCore
import Testing

@testable import NtfyMacCLI

@Suite struct UninstallCommandTests {
  private func populate(_ rig: CLIRig) throws {
    let paths = rig.paths
    try rig.scratch.write("{}", to: "config/config.json")
    try rig.scratch.write("", to: "config/config.json.lock")
    try rig.scratch.write("db", to: "data/ntfy-mac/history.sqlite")
    try rig.scratch.write("{}", to: "data/state/state.json")
    #expect(FileManager.default.fileExists(atPath: paths.configFile.path))
  }

  @Test func withoutATerminalItRequiresYes() async throws {
    let rig = CLIRig()
    try populate(rig)
    let result = await rig.run("uninstall")
    #expect(result.exit == .usage)
    #expect(FileManager.default.fileExists(atPath: rig.paths.configFile.path))
    #expect(await rig.secrets.token() == "tk_secret")
  }

  @Test func yesRemovesEverythingIncludingTheToken() async throws {
    let rig = CLIRig()
    try populate(rig)
    let result = await rig.run("uninstall", "--yes", "--json")
    #expect(result.exit == .success)
    let paths = rig.paths
    for url in [paths.configFile, paths.configLock, paths.dataDirectory, paths.stateDirectory] {
      #expect(!FileManager.default.fileExists(atPath: url.path), "\(url.lastPathComponent)")
    }
    #expect(!FileManager.default.fileExists(atPath: paths.configDirectory.path))
    #expect(await rig.secrets.token() == nil)
    let removeApp = try #require(try result.json()["removeApp"] as? [String])
    #expect(removeApp.contains("brew uninstall --cask ntfy-mac"))
  }

  @Test func theTerminalPromptCanDecline() async throws {
    var rig = CLIRig()
    try populate(rig)
    rig.terminal = Terminal(stdinIsTTY: true, stdoutIsTTY: true)
    rig.prompter = ScriptedPrompter(answers: ["n"])
    let result = await rig.run("uninstall")
    #expect(result.exit == .runtime)
    #expect(FileManager.default.fileExists(atPath: rig.paths.configFile.path))
    #expect(await rig.secrets.token() == "tk_secret")
  }

  @Test func uninstallingTwiceIsFine() async {
    let rig = CLIRig()
    _ = await rig.run("uninstall", "--yes")
    #expect(await rig.run("uninstall", "--yes").exit == .success)
  }
}
