import Foundation
import NtfyCore
import Testing

@testable import NtfyMacCLI

@Suite struct SetupCommandTests {
  @Test func flagsSaveTheURLToConfigAndTheTokenToTheSecretStoreOnly() async throws {
    let rig = CLIRig(configured: false, topics: ["alerts", "ops"])
    let result = await rig.run(
      "setup", "--url", "ntfy.example.com/", "--token", "tk_secret_value", "--json")
    #expect(result.exit == .success)
    let report = try result.json()
    #expect(report["url"] as? String == "https://ntfy.example.com")
    #expect(report["topics"] as? [String] == ["alerts", "ops"])
    #expect(await rig.secrets.token() == "tk_secret_value")
    let config = await rig.config.load()
    #expect(config.url == "https://ntfy.example.com")
    #expect(config.token == nil)
    #expect(!result.stdout.contains("tk_secret_value"))
    #expect(!result.stderr.contains("tk_secret_value"))
  }

  @Test func theLegacyPlaintextTokenIsScrubbedFromTheConfig() async {
    let rig = CLIRig(configured: false)
    await rig.config.save(Config(url: "https://old", token: "tk_old"))
    _ = await rig.run("setup", "--url", "https://new.example.com", "--token", "tk_new")
    #expect(await rig.config.load().token == nil)
  }

  @Test(arguments: [["--url", "https://x.example.com"], ["--token", "tk_x"]])
  func oneFlagWithoutTheOtherIsAUsageError(flags: [String]) async {
    #expect(await CLIRig(configured: false).run(["setup"] + flags).exit == .usage)
  }

  @Test(arguments: ["ftp://x.example.com", "file:///tmp/x", "https://"])
  func aBadURLIsAUsageError(url: String) async {
    let rig = CLIRig(configured: false)
    let result = await rig.run("setup", "--url", url, "--token", "tk_x")
    #expect(result.exit == .usage)
    #expect(await rig.secrets.token() == nil)
  }

  @Test func withoutATerminalSetupDoesNotPrompt() async {
    let result = await CLIRig(configured: false).run("setup")
    #expect(result.exit == .usage)
    #expect(result.stderr.contains("--url <url> --token <token>"))
  }

  @Test func aRejectedTokenSavesNothingAndExitsThree() async {
    let rig = CLIRig(configured: false, topicFailure: .unauthorized)
    let result = await rig.run("setup", "--url", "https://x.example.com", "--token", "tk_bad")
    #expect(result.exit == .auth)
    #expect(await rig.secrets.token() == nil)
    #expect(await rig.config.load().url == nil)
  }

  @Test func anUnreachableServerExitsSeven() async {
    let rig = CLIRig(configured: false, topicFailure: .serverUnreachable)
    let result = await rig.run("setup", "--url", "https://x.example.com", "--token", "tk_x")
    #expect(result.exit == .serverUnreachable)
  }

  @Test func theWizardAsksOnATerminalAndRetriesAfterAFailure() async {
    var rig = CLIRig(configured: false)
    rig.terminal = Terminal(stdinIsTTY: true, stdoutIsTTY: true)
    rig.prompter = ScriptedPrompter(answers: ["ntfy.example.com"], secrets: ["tk_wizard"])
    let result = await rig.run("setup")
    #expect(result.exit == .success)
    #expect(await rig.secrets.token() == "tk_wizard")
    #expect(await rig.config.load().url == "https://ntfy.example.com")
    #expect(result.stdout.contains("Configured: https://ntfy.example.com"))
  }

  @Test func theWizardGivesUpWhenInputEnds() async {
    var rig = CLIRig(configured: false)
    rig.terminal = Terminal(stdinIsTTY: true, stdoutIsTTY: true)
    let result = await rig.run("setup")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("Setup cancelled"))
  }

  @Test func theAppIsStartedButItsAbsenceDoesNotFailSetup() async {
    let rig = CLIRig(configured: false, app: FakeApp(failure: .appUnavailable))
    let result = await rig.run("setup", "--url", "https://x.example.com", "--token", "tk_x")
    #expect(result.exit == .success)
    #expect(result.stderr.contains("not running"))
  }
}
