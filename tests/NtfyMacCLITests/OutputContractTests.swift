import ArgumentParser
import Foundation
import NtfyCore
import Testing

@testable import NtfyMacCLI

@Suite struct OutputContractTests {
  @Test func textModeKeepsDiagnosticsOffStdout() async {
    let rig = CLIRig(topicFailure: .serverUnreachable)
    let result = await rig.run("subscribe")
    #expect(result.stdout.contains("Subscribed topics"))
    #expect(!result.stdout.contains("Could not fetch"))
    #expect(result.stderr.contains("Could not fetch"))
  }

  @Test func jsonModePrintsExactlyOneDocumentOnStdout() async throws {
    let rig = CLIRig(topicFailure: .serverUnreachable)
    let result = await rig.run("subscribe", "--json")
    #expect(result.stdoutLines.count == 1)
    _ = try result.json()
    #expect(result.stderr.contains("Could not fetch"))
  }

  @Test func successfulJSONCommandsWriteNothingToStderr() async {
    let rig = CLIRig()
    for arguments in [["version"], ["config"], ["subscribe"], ["sounds"]] {
      let result = await rig.run(arguments + ["--json"])
      #expect(result.stderr.isEmpty, "\(arguments)")
      #expect(result.stdoutLines.count == 1, "\(arguments)")
    }
  }

  @Test func jsonErrorsUseTheEnvelopeOnStdoutAndAHumanLineOnStderr() async throws {
    let result = await CLIRig(configured: false).run("subscribe", "--json")
    #expect(result.exit == .runtime)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "not-configured")
    #expect(error["message"] as? String == "Not configured. Run: ntfy-mac setup")
    #expect(error["exitCode"] as? Int == 1)
    #expect(Set(error.keys) == ["code", "message", "exitCode"])
    #expect(result.stderr == "Error: Not configured. Run: ntfy-mac setup\n")
  }

  @Test func textErrorsGoOnlyToStderr() async {
    let result = await CLIRig(configured: false).run("subscribe")
    #expect(result.stdout.isEmpty)
    #expect(result.stderr.contains("Not configured"))
  }

  @Test func parseErrorsInJSONModeUseTheEnvelopeToo() async throws {
    let result = await CLIRig().run("config", "sounds", "set", "9", "Pop", "--json")
    #expect(result.exit == .usage)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "usage")
    #expect(error["exitCode"] as? Int == 2)
    #expect(result.stderr.hasPrefix("Error: "))
  }

  @Test func helpGoesToStdoutAndSucceeds() async {
    let result = await CLIRig().run("notify", "--help")
    #expect(result.exit == .success)
    #expect(result.stdout.contains("--dismiss-after"))
    #expect(result.stderr.isEmpty)
  }
}

@Suite struct ExitCodeMappingTests {
  @Test(arguments: [
    (["bogus"], ProcessExit.usage),
    (["notify", "--bogus", "x"], .usage),
    (["notify"], .usage),
    (["config", "sounds", "set", "9", "Pop"], .usage),
  ])
  func usageErrorsExitTwo(arguments: [String], expected: ProcessExit) async {
    #expect(await CLIRig().run(arguments).exit == expected)
    #expect(expected.rawValue == 2)
  }

  @Test func authFailureExitsThree() async {
    let result = await CLIRig(configured: false, topicFailure: .unauthorized).run(
      "setup", "--url", "https://x.example.com", "--token", "tk")
    #expect(result.exit == .auth)
    #expect(result.exit.rawValue == 3)
  }

  @Test func anUnavailableAppExitsFour() async {
    let result = await CLIRig(app: FakeApp(failure: .appUnavailable)).run("notify", "-m", "x")
    #expect(result.exit.rawValue == 4)
  }

  @Test func anUnreachableServerExitsSeven() async {
    var rig = CLIRig(configured: false, topicFailure: .serverUnreachable)
    rig.terminal = Terminal(stdinIsTTY: false, stdoutIsTTY: false)
    let result = await rig.run("setup", "--url", "https://x.example.com", "--token", "tk")
    #expect(result.exit.rawValue == 7)
  }

  @Test func theEnvelopeCarriesTheMappedCode() {
    let report = ErrorReport(NtfyError.unauthorized)
    #expect(report.code == "unauthorized")
    #expect(report.exitCode == 3)
    #expect(ErrorReport(ValidationError("x")).exitCode == 2)
  }

  @Test(arguments: [
    (NtfyError.serverUnreachable, "server-unreachable"), (.appUnavailable, "app-unavailable"),
    (.permissionDenied, "permission-denied"), (.insecureServer, "insecure-server"),
    (.rateLimited(retryAfter: nil), "rate-limited"), (.invalidTopic("x"), "invalid-topic"),
    (.storage("x"), "storage"), (.redirected, "redirected"),
    (.invalidResponse("x"), "invalid-response"),
  ])
  func errorCodesAreStableKebabCase(error: NtfyError, code: String) {
    #expect(error.code == code)
  }
}
