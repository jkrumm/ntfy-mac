import Foundation
import NtfyCore
import Testing

@testable import NtfyMacCLI

@Suite struct PublishCommandTests {
  @Test func publishSendsTheFlagsAndPrintsTheServersAnswer() async throws {
    let rig = CLIRig()
    let result = await rig.run(
      "publish", "builds", "-m", "done", "-t", "CI", "-p", "4", "--tag", "ok", "--tag", "rocket",
      "--click", "https://example.com/run/1", "--json")
    #expect(result.exit == .success)
    let report = try result.json()
    #expect(report["id"] as? String == "pub1")
    #expect(report["topic"] as? String == "builds")
    #expect(report["time"] is String)
    #expect(result.stderr.isEmpty)
  }

  @Test func textModePrintsTheKey() async {
    let result = await CLIRig().run("publish", "builds", "-m", "hi")
    #expect(result.stdout == "Published builds/pub1.\n")
  }

  @Test func aDashReadsTheMessageFromStdin() async throws {
    var rig = CLIRig()
    rig.stdin = Data("line one\nline two\n\n".utf8)
    let probe = ProbePublisher()
    let environment = rig.environment
    var wired = environment
    wired.publisher = { _, _, _ in probe }
    let capture = Capture()
    let exit = await CLIEntry.run(["publish", "builds", "-m", "-"], environment: wired) {
      Output(json: $0, stdout: capture.out, stderr: capture.err)
    }
    #expect(exit == .success)
    let request = try #require(await probe.requests.first)
    #expect(request.message == "line one\nline two")
    #expect(request.topic == "builds")
  }

  @Test func stdinThatIsATerminalOrEmptyIsAUsageError() async {
    var rig = CLIRig()
    rig.terminal = Terminal(stdinIsTTY: true, stdoutIsTTY: true)
    #expect(await rig.run("publish", "builds", "-m", "-").exit == .usage)
    var empty = CLIRig()
    empty.stdin = Data("\n".utf8)
    #expect(await empty.run("publish", "builds", "-m", "-").exit == .usage)
  }

  @Test(arguments: [
    (NtfyError.unauthorized, ProcessExit.auth), (.serverUnreachable, .serverUnreachable),
    (.rateLimited(retryAfter: 3), .runtime), (.insecureServer, .runtime),
  ])
  func serverFailuresMapToTheirExitCodes(error: NtfyError, exit: ProcessExit) async throws {
    var rig = CLIRig()
    rig.publishFailure = error
    let result = await rig.run("publish", "builds", "-m", "x", "--json")
    #expect(result.exit == exit)
    let envelope = try #require(try result.json()["error"] as? [String: Any])
    #expect(envelope["code"] as? String == error.code)
  }

  @Test func publishNeedsAConfiguredServer() async {
    let result = await CLIRig(configured: false).run("publish", "builds", "-m", "x")
    #expect(result.exit == .runtime)
  }

  @Test(arguments: [
    ["publish"], ["publish", "builds"], ["publish", "builds", "-m", ""],
    ["publish", "bad topic", "-m", "x"], ["publish", "builds", "-m", "x", "-p", "6"],
    ["publish", "builds", "-m", "x", "--click", "ftp://example.com"],
  ])
  func invalidInvocationsAreUsageErrors(arguments: [String]) async {
    #expect(await CLIRig().run(arguments).exit == .usage, "\(arguments)")
  }
}

private actor ProbePublisher: NtfyPublishing {
  private(set) var requests: [PublishRequest] = []

  func publish(_ request: PublishRequest) async throws(NtfyError) -> PublishedMessage {
    requests.append(request)
    return PublishedMessage(id: "p", topic: request.topic, time: Date())
  }
}
