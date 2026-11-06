import NtfyAppLogic
import NtfyCore
import NtfyIPC
import NtfyTesting
import Testing

@Suite struct IPCUpdateTests {
  private func request(check: Bool) -> Request {
    Request(id: "1", command: .update, update: UpdatePayload(check: check))
  }

  private let found = UpdateStatus(
    channel: .direct, currentVersion: "2.0.0", latestVersion: "2.1.0", updateAvailable: true)

  @Test func aCheckProbesWithoutStartingTheInteractiveFlow() async throws {
    let updater = ScriptedUpdater(status: UpdateStatus(channel: .direct), probe: .success(found))
    let response = await HandlerRig(updates: updater).send(request(check: true))
    let result = try #require(response.result?.update)
    #expect(result.updateAvailable && result.latestVersion == "2.1.0" && result.reason == nil)
    #expect(updater.calls == [.status, .probe])
  }

  @Test func withoutCheckTheInteractiveFlowStartsAndTheAnswerIsImmediate() async throws {
    let updater = ScriptedUpdater(status: found)
    let response = await HandlerRig(updates: updater).send(request(check: false))
    #expect(response.status == .success)
    #expect(try #require(response.result?.update).channel == "direct")
    #expect(updater.calls == [.status, .interactive])
  }

  @Test(arguments: UpdateUnavailableReason.allCases, [true, false])
  func aReasonIsASuccessThatRunsNothing(reason: UpdateUnavailableReason, check: Bool) async throws {
    let updater = ScriptedUpdater(
      status: UpdateStatus(channel: .direct, currentVersion: "2.0.0", reason: reason))
    let response = await HandlerRig(updates: updater).send(request(check: check))
    #expect(response.status == .success)
    #expect(try #require(response.result?.update).reason == reason.rawValue)
    #expect(updater.calls == [.status])
  }

  @Test func aFailedProbeIsAnInternalError() async {
    let updater = ScriptedUpdater(
      status: UpdateStatus(channel: .direct), probe: .failure(.serverUnreachable))
    let response = await HandlerRig(updates: updater).send(request(check: true))
    #expect(response.status == .error && response.code == .internalError)
  }

  @Test func aMissingPayloadIsABadRequest() async {
    let updater = ScriptedUpdater(status: UpdateStatus(channel: .direct))
    let response = await HandlerRig(updates: updater).send(Request(id: "1", command: .update))
    #expect(response.code == .badRequest)
    #expect(updater.calls.isEmpty)
  }

  @Test func aBuildWithoutAnUpdaterSaysSo() async {
    #expect(await HandlerRig().send(request(check: true)).code == .appUnavailable)
  }
}
