import Foundation
import NtfyCore
import NtfyIPC
import Testing

@testable import NtfyMacCLI

@Suite struct NotifyCommandTests {
  private func sentPayload(_ rig: CLIRig) async throws -> NotifyPayload {
    let calls = await rig.app.calls
    let call = try #require(calls.first { $0.request.command == .notify })
    return try #require(call.request.notify)
  }

  @Test func flagsBuildThePayload() async throws {
    let rig = CLIRig()
    let result = await rig.run(
      "notify", "-t", "Alert", "-m", "Disk full", "-p", "5", "--tag", "warning", "--tag", "skull",
      "--url", "https://example.com/x", "-d", "10")
    #expect(result.exit == .success)
    #expect(result.stdout == "Notification sent.\n")
    let payload = try await sentPayload(rig)
    #expect(payload.title == "Alert")
    #expect(payload.body == "Disk full")
    #expect(payload.priority == 5)
    #expect(payload.tags == ["warning", "skull"])
    #expect(payload.clickURL?.absoluteString == "https://example.com/x")
    #expect(payload.dismissAfterSeconds == 10)
  }

  @Test func theDefaultsAre1xs() async throws {
    let rig = CLIRig()
    _ = await rig.run("notify", "-m", "hi")
    let payload = try await sentPayload(rig)
    #expect(payload.title == "ntfy-mac")
    #expect(payload.priority == 3)
    #expect(payload.dismissAfterSeconds == nil)
  }

  @Test func theMessageIsRequiredWithoutJSON() async {
    let result = await CLIRig().run("notify", "-t", "only a title")
    #expect(result.exit == .usage)
  }

  @Test(arguments: [
    ["-p", "0"], ["-p", "6"], ["-d", "-1"], ["--url", "javascript:alert(1)"],
    ["--url", "file:///etc/passwd"], ["--bogus", "x"],
  ])
  func badValuesAreUsageErrors(extra: [String]) async {
    let rig = CLIRig()
    let result = await rig.run(["notify", "-m", "x"] + extra)
    #expect(result.exit == .usage)
    #expect(await rig.app.calls.isEmpty)
  }

  @Test func jsonReadsThePayloadFromStdin() async throws {
    var rig = CLIRig()
    rig.stdin = Data(
      #"{"title":"T","body":"B","priority":4,"tags":["a","b"],"clickUrl":"https://e.com","dismissAfter":7}"#
        .utf8)
    let result = await rig.run("notify", "--json")
    #expect(result.exit == .success)
    #expect(try result.json()["posted"] as? Bool == true)
    let payload = try await sentPayload(rig)
    #expect(payload.title == "T")
    #expect(payload.body == "B")
    #expect(payload.priority == 4)
    #expect(payload.tags == ["a", "b"])
    #expect(payload.clickURL?.absoluteString == "https://e.com")
    #expect(payload.dismissAfterSeconds == 7)
  }

  @Test func jsonOnATerminalIsAUsageErrorInsteadOfBlocking() async {
    var rig = CLIRig()
    rig.terminal = Terminal(stdinIsTTY: true, stdoutIsTTY: false)
    let result = await rig.run("notify", "--json")
    #expect(result.exit == .usage)
    #expect(result.stderr.contains("stdin is a terminal"))
    #expect(await rig.app.calls.isEmpty)
  }

  @Test(arguments: ["", "not json", "[1]", #"{"title":"no body"}"#, #"{"body":"x","priority":9}"#])
  func badJSONPayloadsAreUsageErrors(payload: String) async {
    var rig = CLIRig()
    rig.stdin = Data(payload.utf8)
    #expect(await rig.run("notify", "--json").exit == .usage)
  }

  @Test func jsonCannotBeCombinedWithFlags() async {
    var rig = CLIRig()
    rig.stdin = Data(#"{"body":"x"}"#.utf8)
    #expect(await rig.run("notify", "--json", "-m", "y").exit == .usage)
  }

  @Test func deniedPermissionExitsFour() async {
    let app = FakeApp()
    await app.reply(
      to: .notify,
      with: .failure(id: "x", code: .permissionDenied, message: "notifications are not allowed"))
    let result = await CLIRig(app: app).run("notify", "-m", "x")
    #expect(result.exit == .appUnavailable)
    #expect(result.stderr.contains("notifications are not allowed"))
  }

  @Test func anAppThatCannotBeReachedExitsFour() async {
    let result = await CLIRig(app: FakeApp(failure: .appUnavailable)).run("notify", "-m", "x")
    #expect(result.exit == .appUnavailable)
  }

  @Test func aPausedAppReportsTheNotificationAsHeldBack() async {
    let app = FakeApp()
    await app.reply(
      to: .notify,
      with: .success(id: "x", result: ResultPayload(notify: NotifyResult(posted: false))))
    let result = await CLIRig(app: app).run("notify", "-m", "x")
    #expect(result.exit == .success)
    #expect(result.stdout.contains("paused"))
  }
}
