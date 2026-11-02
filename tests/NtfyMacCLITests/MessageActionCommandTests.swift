import Foundation
import NtfyCore
import NtfyIPC
import Testing

@testable import NtfyMacCLI

@Suite struct RemindCommandTests {
  @Test func inSchedulesRelativeToNowThroughTheApp() async throws {
    let rig = CLIRig()
    let result = await rig.run("remind", "alerts", "a1", "--in", "1h30m", "--json")
    #expect(result.exit == .success)
    let call = try #require(await rig.app.calls.first)
    #expect(call.request.command == .remind)
    #expect(call.launch)
    let expected = rig.clock.now().addingTimeInterval(5400)
    #expect(call.request.remind == RemindPayload(topic: "alerts", id: "a1", until: expected))
    let report = try result.json()
    #expect(report["topic"] as? String == "alerts")
    #expect(report["id"] as? String == "a1")
    #expect(report["remindAt"] is String)
  }

  @Test func untilTakesAFutureISOTime() async throws {
    let rig = CLIRig()
    let result = await rig.run("remind", "alerts", "a1", "--until", "2030-01-01T08:00:00Z")
    #expect(result.exit == .success)
    #expect(result.stdout.hasPrefix("Will remind about alerts/a1 at 2030-01-01T08:00:00Z"))
    let call = try #require(await rig.app.calls.first)
    #expect(call.request.remind?.until == Date(timeIntervalSince1970: 1_893_484_800))
  }

  @Test(arguments: [
    ["remind", "alerts", "a1"],
    ["remind", "alerts", "a1", "--in", "1h", "--until", "2030-01-01T08:00:00Z"],
    ["remind", "alerts", "a1", "--in", "soon"], ["remind", "alerts", "a1", "--until", "tomorrow"],
    ["remind", "alerts", "a1", "--until", "2001-01-01T00:00:00Z"],
    ["remind", "bad topic", "a1", "--in", "1h"], ["remind", "alerts"],
  ])
  func badFormsAreUsageErrorsAndNeverReachTheApp(arguments: [String]) async {
    let rig = CLIRig()
    #expect(await rig.run(arguments).exit == .usage, "\(arguments)")
    #expect(await rig.app.calls.isEmpty)
  }

  @Test func anUnknownMessageIsNotFoundAndADownAppIsExitFour() async throws {
    let app = FakeApp()
    await app.reply(to: .remind, with: .failure(id: "x", code: .notFound, message: "no message"))
    let missing = await CLIRig(app: app).run("remind", "alerts", "nope", "--in", "1h", "--json")
    #expect(missing.exit == .runtime)
    let error = try #require(try missing.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "not-found")
    let down = CLIRig(app: FakeApp(failure: .appUnavailable))
    #expect(await down.run("remind", "alerts", "a1", "--in", "1h").exit == .appUnavailable)
  }
}

@Suite struct DeleteCommandTests {
  @Test func deleteOneGoesThroughTheAppAndLaunchesIt() async throws {
    let rig = CLIRig()
    let result = await rig.run("delete", "alerts", "a1", "--json")
    #expect(result.exit == .success)
    #expect(try result.json()["deleted"] as? Int == 1)
    let call = try #require(await rig.app.calls.first)
    #expect(call.request.command == .delete)
    #expect(call.request.delete == DeletePayload(topic: "alerts", id: "a1"))
    #expect(call.launch)
    #expect(await rig.run("delete", "alerts", "a1").stdout == "Deleted alerts/a1.\n")
  }

  @Test func deleteAllCarriesTheTopicWithoutAnIdAndReportsTheCount() async throws {
    let app = FakeApp()
    await app.reply(
      to: .delete, with: .success(id: "x", result: ResultPayload(delete: DeleteResult(deleted: 4))))
    let rig = CLIRig(app: app)
    let result = await rig.run("delete", "--topic", "alerts", "--all", "--json")
    #expect(try result.json()["deleted"] as? Int == 4)
    let call = try #require(await app.calls.first)
    #expect(call.request.delete == DeletePayload(topic: "alerts"))
    #expect(
      await rig.run("delete", "--all", "--topic", "alerts").stdout
        == "Deleted 4 message(s) of alerts.\n")
  }

  @Test func anUnknownMessageIsNotFoundAndADownAppIsExitFour() async throws {
    let app = FakeApp()
    await app.reply(to: .delete, with: .failure(id: "x", code: .notFound, message: "no message"))
    let result = await CLIRig(app: app).run("delete", "alerts", "nope", "--json")
    #expect(result.exit == .runtime)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "not-found")
    #expect(
      await CLIRig(app: FakeApp(failure: .appUnavailable)).run("delete", "a", "b").exit
        == .appUnavailable)
  }

  @Test func anOlderAppIsRecognisedByItsInvalidFrameAnswer() async throws {
    let app = FakeApp()
    await app.reply(
      to: .delete, with: .failure(id: "", code: .badRequest, message: IPC.invalidFrameMessage))
    let result = await CLIRig(app: app).run("delete", "alerts", "a1", "--json")
    #expect(result.exit == .runtime)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "app-outdated")
    #expect((error["message"] as? String)?.contains("too old") == true)
  }

  @Test func anotherBadRequestStaysAUsageError() async {
    let app = FakeApp()
    await app.reply(to: .delete, with: .failure(id: "x", code: .badRequest, message: "other"))
    #expect(await CLIRig(app: app).run("delete", "alerts", "a1").exit == .usage)
  }

  @Test(arguments: [
    ["delete"], ["delete", "alerts"], ["delete", "--all"], ["delete", "--topic", "alerts"],
    ["delete", "alerts", "a1", "--all"], ["delete", "--all", "alerts", "--topic", "alerts"],
    ["delete", "alerts", "a1", "--topic", "x"], ["delete", "--all", "--topic", "bad topic"],
  ])
  func deleteNeedsExactlyOneForm(arguments: [String]) async {
    let rig = CLIRig()
    #expect(await rig.run(arguments).exit == .usage, "\(arguments)")
    #expect(await rig.app.calls.isEmpty)
  }
}
