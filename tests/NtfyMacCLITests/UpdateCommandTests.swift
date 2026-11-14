import Foundation
import NtfyCore
import NtfyIPC
import Testing

@testable import NtfyMacCLI

@Suite struct UpdateCommandTests {
  private func reply(
    _ status: UpdateStatusPayload, to app: FakeApp, as command: Command = .update
  ) async {
    await app.reply(to: command, with: .success(id: "x", result: ResultPayload(update: status)))
  }

  @Test func checkAsksTheAppToProbeAndReportsWhatItFound() async throws {
    let app = FakeApp()
    await reply(
      UpdateStatusPayload(
        channel: "direct", currentVersion: "2.0.0", latestVersion: "2.1.0", updateAvailable: true),
      to: app)
    let result = await CLIRig(app: app).run("update", "--check", "--json")
    #expect(result.exit == .success)
    let json = try result.json()
    #expect(json["updateAvailable"] as? Bool == true && json["latest"] as? String == "2.1.0")
    #expect(json["started"] as? Bool == false)
    let call = try #require(await app.calls.first)
    #expect(call.request.update == UpdatePayload(check: true) && call.launch)
  }

  @Test func withoutCheckItStartsTheAppsFlowAndReturnsAtOnce() async throws {
    let app = FakeApp()
    await reply(UpdateStatusPayload(channel: "direct", currentVersion: "2.0.0"), to: app)
    let result = await CLIRig(app: app).run("update")
    #expect(result.exit == .success)
    #expect(result.stdout.contains("follow the prompt"))
    #expect(try #require(await app.calls.first).request.update == UpdatePayload(check: false))
  }

  @Test func upToDateIsSaidPlainly() async {
    let result = await CLIRig().run("update", "--check")
    #expect(result.stdout.contains("Up to date"))
  }

  @Test(arguments: [
    ("unsigned", "Developer ID"), ("homebrew", "brew update"),
    ("disabled", "NTFY_MAC_NO_SELF_UPDATE"), ("team-mismatch", "different team"),
  ])
  func aReasonIsExplainedWithExitZero(reason: String, words: String) async throws {
    let app = FakeApp()
    await reply(
      UpdateStatusPayload(channel: "direct", currentVersion: "2.0.0", reason: reason), to: app)
    let text = await CLIRig(app: app).run("update")
    #expect(text.exit == .success && text.stdout.contains(words))
    let json = try await CLIRig(app: app).run("update", "--json").json()
    #expect(json["reason"] as? String == reason && json["started"] as? Bool == false)
  }

  @Test func theEnvironmentSwitchAnswersWithoutTheApp() async throws {
    let app = FakeApp()
    var rig = CLIRig(app: app)
    rig.variables = ["NTFY_MAC_NO_SELF_UPDATE": "1"]
    let result = await rig.run("update", "--json")
    #expect(result.exit == .success)
    #expect(try result.json()["reason"] as? String == "disabled")
    #expect(await app.calls.isEmpty)
  }

  @Test func anOlderAppIsRecognisedByItsInvalidFrameAnswer() async throws {
    let app = FakeApp()
    await app.reply(
      to: .update, with: .failure(id: "", code: .badRequest, message: IPC.invalidFrameMessage))
    let result = await CLIRig(app: app).run("update", "--json")
    #expect(result.exit == .runtime)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "app-outdated")
  }

  @Test func aDownAppIsExitFour() async {
    let result = await CLIRig(app: FakeApp(failure: .appUnavailable)).run("update")
    #expect(result.exit == .appUnavailable)
  }

  @Test func aHomebrewCopyNeverTalksToTheApp() async {
    let app = FakeApp()
    var rig = CLIRig(app: app)
    rig.executablePath = "/opt/homebrew/Cellar/ntfy-mac/2.0.0/NtfyMac.app/Contents/MacOS/ntfy-mac"
    _ = await rig.run("update")
    _ = await rig.run("update", "--check")
    #expect(await app.calls.isEmpty)
  }
}
