import Foundation
import NtfyCore
import NtfyIPC
import Testing

@testable import NtfyMacCLI

@Suite struct WaitCommandTests {
  private func message(_ result: RunResult) throws -> [String: Any] { try result.json() }

  @Test func aMessageThatArrivesAfterTheStartMatches() async throws {
    let rig = CLIRig()
    let result = await rig.runAdvancing(
      ["wait", "--topic", "alerts", "--match", "approved", "--json"]
    ) { rig in
      await rig.add("alerts", id: "other", body: "something else")
      await rig.add("alerts", id: "yes", body: "Deploy APPROVED by Johannes")
    }
    #expect(result.exit == .success)
    let found = try message(result)
    #expect(found["id"] as? String == "yes")
    #expect(await rig.app.calls.isEmpty)
  }

  @Test func messagesAlreadyInTheHistoryNeverMatch() async throws {
    let rig = CLIRig()
    await rig.add("alerts", id: "early", body: "approved", age: 5)
    let result = await rig.runAdvancing([
      "wait", "--topic", "alerts", "--match", "approved", "--timeout", "3", "--json",
    ])
    #expect(result.exit == .runtime)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "timeout")
  }

  @Test func titleAndRegexAreSearched() async throws {
    let rig = CLIRig()
    let result = await rig.runAdvancing(
      ["wait", "--topic", "alerts", "--match", "/^release v\\d+$/", "--json"]
    ) { rig in
      await rig.add("alerts", id: "no", body: "release v1 done")
      await rig.add("alerts", id: "yes", body: "details", title: "release v42")
    }
    #expect(try message(result)["id"] as? String == "yes")
  }

  @Test func otherTopicsAndLowPrioritiesAreIgnored() async throws {
    let rig = CLIRig()
    let result = await rig.runAdvancing(
      ["wait", "--topic", "alerts", "--match", "go", "--min-priority", "4", "--json"]
    ) { rig in
      await rig.add("builds", id: "wrong-topic", body: "go", priority: 5)
      await rig.add("alerts", id: "too-low", body: "go", priority: 3)
      await rig.add("alerts", id: "right", body: "go", priority: 4)
    }
    #expect(try message(result)["id"] as? String == "right")
  }

  @Test func timeoutExitsOneWithTheTimeoutCode() async throws {
    let rig = CLIRig()
    let result = await rig.runAdvancing([
      "wait", "--topic", "alerts", "--match", "never", "--timeout", "2", "--json",
    ])
    #expect(result.exit == .runtime)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "timeout")
    #expect(error["exitCode"] as? Int == 1)
    #expect(rig.clock.now().timeIntervalSince(Date(timeIntervalSince1970: 1_700_000_000)) >= 2)
  }

  @Test func ackAcknowledgesTheMatchThroughTheApp() async throws {
    let rig = CLIRig()
    let result = await rig.runAdvancing(
      ["wait", "--topic", "alerts", "--match", "ok", "--ack"]
    ) { rig in
      await rig.add("alerts", id: "m9", body: "ok")
    }
    #expect(result.exit == .success)
    #expect(result.stdout.contains("alerts/m9"))
    let call = try #require(await rig.app.calls.first)
    #expect(call.request.command == .ack)
    #expect(call.request.ack == MessageTarget(topic: "alerts", id: "m9"))
  }

  @Test func ackWithTheAppDownStillPrintsTheMatchThenFails() async throws {
    let rig = CLIRig(app: FakeApp(failure: .appUnavailable))
    let result = await rig.runAdvancing(
      ["wait", "--topic", "alerts", "--match", "ok", "--ack", "--json"]
    ) { rig in
      await rig.add("alerts", id: "m9", body: "ok")
    }
    #expect(result.exit == .appUnavailable)
    #expect(result.stdout.contains("\"id\":\"m9\""))
  }

  @Test(arguments: [
    ["wait", "--match", "x"], ["wait", "--topic", "alerts"],
    ["wait", "--topic", "alerts", "--match", "/(/"],
    ["wait", "--topic", "alerts", "--match", ""],
    ["wait", "--topic", "alerts", "--match", "x", "--timeout", "0"],
    ["wait", "--topic", "alerts", "--match", "x", "--timeout", "soon"],
    ["wait", "--topic", "alerts", "--match", "x", "--min-priority", "9"],
    ["wait", "--topic", "bad topic", "--match", "x"],
  ])
  func invalidInvocationsAreUsageErrors(arguments: [String]) async {
    #expect(await CLIRig().run(arguments).exit == .usage, "\(arguments)")
  }

  @Test func pathLikeTextIsASubstringNotARegex() throws {
    let matcher = try MessageMatcher("/usr/bin")
    let hit = NtfyMessage(id: "1", topic: "t", time: Date(), body: "see /usr/bin/env")
    #expect(matcher.matches(hit))
    let ignoreCase = try MessageMatcher("/WARN/i")
    #expect(ignoreCase.matches(NtfyMessage(id: "2", topic: "t", time: Date(), body: "a warning")))
  }
}
