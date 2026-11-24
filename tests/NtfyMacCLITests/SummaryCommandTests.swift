import Foundation
import NtfyCore
import NtfyTesting
import Testing

@testable import NtfyMacCLI

@Suite struct SummaryCommandTests {
  private func configured(_ rig: CLIRig, key: String? = "door") async {
    await rig.config.update {
      $0.summary = SummarySettings(enabled: true, endpoint: "https://gw.example.com/anthropic")
    }
    if let key { await rig.summaryKeys.setToken(key) }
  }

  private func shown(_ rig: CLIRig, id: String, age: TimeInterval = 600, priority: Int = 3) async {
    await rig.add("ci", id: id, body: "body", title: "T\(id)", priority: priority, age: age)
    await rig.store.markNotified(topic: "ci", id: id, at: rig.clock.now())
  }

  @Test func theModelsSummaryIsPrinted() async throws {
    let rig = CLIRig()
    await configured(rig)
    for index in 0..<10 { await shown(rig, id: "m\(index)") }
    let result = await rig.run("summary", "--since", "1h", "--json")
    #expect(result.exit == .success, "\(result.stderr)")
    let document = try result.json()
    #expect(document["count"] as? Int == 10)
    #expect(document["source"] as? String == "model")
    #expect(document["summary"] as? String == "summary")
    #expect(await rig.summarizer.calls.first?.count == 10)
  }

  @Test func theTextShowsTheTitleAndTheSummary() async {
    let rig = CLIRig()
    await configured(rig)
    for index in 0..<3 { await shown(rig, id: "m\(index)") }
    let result = await rig.run("summary")
    #expect(result.stdout == "While you were away · 3 messages\nsummary\n")
  }

  @Test func withoutTheDigestConfiguredTheCountsAreShownAndNoRequestIsMade() async throws {
    let rig = CLIRig()
    for index in 0..<4 { await shown(rig, id: "m\(index)") }
    await shown(rig, id: "urgent", priority: 5)
    let result = await rig.run("summary", "--json")
    let document = try result.json()
    #expect(document["source"] as? String == "deterministic")
    #expect(document["summary"] as? String == "5 messages: ci 5, 1 unacknowledged")
    #expect(await rig.summarizer.calls.isEmpty)
  }

  @Test func aFailingEndpointFallsBackAndSaysWhy() async throws {
    let rig = CLIRig()
    await configured(rig)
    await rig.summarizer.setOutcome(.failure(.serverUnreachable))
    for index in 0..<3 { await shown(rig, id: "m\(index)") }
    let result = await rig.run("summary", "--json")
    #expect(result.exit == .success)
    let document = try result.json()
    #expect(document["source"] as? String == "deterministic")
    #expect(document["failure"] is String)
    let text = await rig.run("summary")
    #expect(text.stdout.contains("(model unavailable:"))
  }

  @Test func theWindowIsTheGivenDuration() async throws {
    let rig = CLIRig()
    await shown(rig, id: "recent", age: 600)
    await shown(rig, id: "old", age: 3 * 3600)
    let document = try await rig.run("summary", "--since", "1h", "--json").json()
    #expect(document["count"] as? Int == 1)
    let wider = try await rig.run("summary", "--since", "1d", "--json").json()
    #expect(wider["count"] as? Int == 2)
  }

  @Test func messagesThatWereNeverShownDoNotCount() async throws {
    let rig = CLIRig()
    await rig.add("ci", id: "held", age: 60)
    let document = try await rig.run("summary", "--json").json()
    #expect(document["count"] as? Int == 0)
    #expect(document["source"] as? String == "none")
  }

  @Test func aBadWindowIsAUsageError() async {
    let result = await CLIRig().run("summary", "--since", "soon")
    #expect(result.exit == .usage)
  }

  @Test func theTestSendsOneRequestAndPrintsTheAnswer() async throws {
    let rig = CLIRig()
    await configured(rig)
    let result = await rig.run("summary", "--test", "--json")
    #expect(result.exit == .success, "\(result.stderr)")
    let document = try result.json()
    #expect(document["ok"] as? Bool == true)
    #expect(await rig.summarizer.calls.count == 1)
  }

  @Test func theTestWithoutAKeyExplainsWhatToDo() async {
    let rig = CLIRig()
    await configured(rig, key: nil)
    let result = await rig.run("summary", "--test")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("config summary-key set"))
    #expect(await rig.summarizer.calls.isEmpty)
  }

  @Test func theTestWithoutAnEndpointExplainsWhatToDo() async {
    let result = await CLIRig().run("summary", "--test")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("config set summary.endpoint"))
  }

  @Test func theTestShowsTheEndpointsError() async {
    let rig = CLIRig()
    await configured(rig)
    await rig.summarizer.setOutcome(.failure(.unauthorized))
    let result = await rig.run("summary", "--test")
    #expect(result.exit == .auth)
  }

  @Test func withoutAnyHistoryTheAnswerIsEmptyNotAnError() async throws {
    var rig = CLIRig()
    rig.historyAbsent = true
    let result = await rig.run("summary", "--json")
    #expect(result.exit == .success)
    #expect(try result.json()["count"] as? Int == 0)
  }
}

@Suite struct ConfigSummaryTests {
  @Test func everyKeyIsSetAndReadBack() async {
    let rig = CLIRig()
    for (key, value) in [
      ("summary.enabled", "on"), ("summary.endpoint", "https://gw.example.com/anthropic/"),
      ("summary.model", "haiku"), ("summary.minAwayMinutes", "30"), ("summary.minMessages", "5"),
    ] {
      let result = await rig.run("config", "set", key, value)
      #expect(result.exit == .success, "\(key): \(result.stderr)")
    }
    let summary = await rig.config.load().summary
    #expect(
      summary
        == SummarySettings(
          enabled: true, endpoint: "https://gw.example.com/anthropic", model: "haiku",
          minAwayMinutes: 30, minMessages: 5))
    let got = await rig.run("config", "get", "summary.endpoint")
    #expect(got.stdout == "summary.endpoint = https://gw.example.com/anthropic\n")
  }

  @Test func resetRestoresTheDefaultAndClearsTheEndpoint() async {
    let rig = CLIRig()
    _ = await rig.run("config", "set", "summary.endpoint", "https://gw.example.com")
    _ = await rig.run("config", "set", "summary.model", "haiku")
    _ = await rig.run("config", "reset", "summary.endpoint")
    _ = await rig.run("config", "reset", "summary.model")
    #expect(await rig.config.load().summary == SummarySettings())
  }

  @Test(arguments: [
    ("summary.enabled", "maybe"), ("summary.endpoint", "gateway"), ("summary.model", " "),
    ("summary.minAwayMinutes", "-1"), ("summary.minMessages", "0"),
  ]) func badValuesAreUsageErrors(key: String, value: String) async {
    let rig = CLIRig()
    let result = await rig.run("config", "set", key, value)
    #expect(result.exit == .usage, "\(key)")
    #expect(await rig.config.load().summary == SummarySettings())
  }

  @Test func plainHttpIsRefusedWithoutTheOptIn() async {
    let rig = CLIRig()
    let refused = await rig.run("config", "set", "summary.endpoint", "http://gw.example.com")
    #expect(refused.exit == .runtime)
    #expect(await rig.config.load().summary.endpoint == nil)
    _ = await rig.run("config", "set", "allowInsecure", "on")
    let allowed = await rig.run("config", "set", "summary.endpoint", "http://gw.example.com")
    #expect(allowed.exit == .success)
  }

  @Test func theKeyIsReadFromStdinAndStaysOutOfTheConfig() async throws {
    var rig = CLIRig()
    rig.stdin = Data(" sk-secret\n".utf8)
    let result = await rig.run("config", "summary-key", "set")
    #expect(result.exit == .success, "\(result.stderr)")
    #expect(await rig.summaryKeys.token() == "sk-secret")
    #expect(!result.stdout.contains("sk-secret"))
    #expect(await rig.secrets.token() == "tk_secret")
    let status = try await rig.run("config", "summary-key", "--json").json()
    #expect(status["stored"] as? Bool == true)
  }

  @Test func aKeyFromATerminalOrNothingIsAUsageError() async {
    var rig = CLIRig()
    rig.terminal = Terminal(stdinIsTTY: true, stdoutIsTTY: true)
    #expect(await rig.run("config", "summary-key", "set").exit == .usage)
    rig.terminal = Terminal(stdinIsTTY: false, stdoutIsTTY: false)
    rig.stdin = Data("\n".utf8)
    #expect(await rig.run("config", "summary-key", "set").exit == .usage)
    #expect(await rig.summaryKeys.token() == nil)
  }

  @Test func clearRemovesTheKey() async {
    let rig = CLIRig()
    await rig.summaryKeys.setToken("sk")
    #expect(await rig.run("config", "summary-key", "clear").exit == .success)
    #expect(await rig.summaryKeys.token() == nil)
  }

  @Test func theEnvironmentKeyWinsOverTheKeychainForARun() async throws {
    let base = InMemorySecretStore(token: "stored")
    let store = EnvironmentSecretStore(override: "from-env", base: base)
    #expect(try await store.token() == "from-env")
    try await store.setToken("new")
    #expect(await base.token() == "new")
    #expect(try await EnvironmentSecretStore(override: nil, base: base).token() == "new")
    #expect(try await EnvironmentSecretStore(override: "", base: base).token() == "new")
  }
}
