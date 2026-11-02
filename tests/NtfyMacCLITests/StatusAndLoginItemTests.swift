import Foundation
import NtfyCore
import NtfyIPC
import Testing

@testable import NtfyMacCLI

@Suite struct StatusAndLoginItemTests {
  private func appStatus(
    connection: String = "connected", pausedUntil: Date? = nil,
    permission: PermissionSummary? = PermissionSummary(usable: true)
  ) -> Response {
    .success(
      id: "s",
      result: ResultPayload(
        status: StatusResult(
          connection: connection, pausedUntil: pausedUntil, appVersion: Version.current,
          permission: permission)))
  }

  // MARK: status

  @Test func statusAsksTheAppWithoutLaunchingIt() async throws {
    let app = FakeApp()
    await app.reply(to: .status, with: appStatus(connection: "connecting"))
    let rig = CLIRig(app: app)
    await rig.add("alerts", id: "a1", age: 30)
    await rig.add("builds", id: "b1", age: 5)
    await rig.store.markRead(topic: "alerts", id: "a1")
    let result = await rig.run("status", "--json")
    #expect(result.exit == .success)
    let report = try result.json()
    #expect(report["running"] as? Bool == true)
    #expect(report["connection"] as? String == "connecting")
    #expect(report["appVersion"] as? String == Version.current)
    #expect(report["server"] as? String == CLIRig.serverURL)
    #expect(report["topics"] as? [String] == ["alerts", "builds"])
    #expect((report["permission"] as? [String: Any])?["usable"] as? Bool == true)
    let history = try #require(report["history"] as? [String: Any])
    #expect(history["total"] as? Int == 2)
    #expect(history["unread"] as? Int == 1)
    #expect(history["unacknowledged"] as? Int == 2)
    #expect(history["lastMessageAt"] is String)
    #expect(await app.calls.allSatisfy { !$0.launch && $0.request.command == .status })
  }

  @Test func withTheAppDownStatusStillReportsWhatTheFilesKnow() async throws {
    let rig = CLIRig(app: FakeApp(failure: .appUnavailable))
    await rig.add("alerts", id: "a1")
    await rig.config.update { $0.pausedUntil = Date(timeIntervalSince1970: 1_700_003_600) }
    let result = await rig.run("status", "--json")
    #expect(result.exit == .success)
    let report = try result.json()
    #expect(report["running"] as? Bool == false)
    #expect(report["connection"] is NSNull)
    #expect(report["permission"] is NSNull)
    #expect(report["paused"] as? Bool == true)
    #expect(report["pausedUntil"] as? String == "2023-11-14T23:13:20Z")
    #expect((report["history"] as? [String: Any])?["total"] as? Int == 1)
    #expect(result.stderr.isEmpty)
    #expect(await rig.run("status").stdout.contains("not running"))
  }

  @Test func requireRunningExitsFourButStillPrintsTheReport() async throws {
    let rig = CLIRig(app: FakeApp(failure: .appUnavailable))
    let result = await rig.run("status", "--require-running", "--json")
    #expect(result.exit == .appUnavailable)
    #expect(try result.json()["running"] as? Bool == false)
    let running = await CLIRig().run("status", "--require-running")
    #expect(running.exit == .success)
  }

  @Test func statusWorksUnconfiguredWithNoHistory() async throws {
    var rig = CLIRig(configured: false, app: FakeApp(failure: .appUnavailable))
    rig.historyAbsent = true
    let report = try await rig.run("status", "--json").json()
    #expect(report["configured"] as? Bool == false)
    #expect(report["server"] is NSNull)
    #expect((report["history"] as? [String: Any])?["total"] as? Int == 0)
  }

  @Test func theAppsPauseWinsAndLocalTopicsAreListed() async throws {
    let until = Date(timeIntervalSince1970: 1_700_007_200)
    let app = FakeApp()
    await app.reply(to: .status, with: appStatus(pausedUntil: until))
    let rig = CLIRig(app: app)
    await rig.config.update { $0.extraTopics = ["mine"] }
    let report = try await rig.run("status", "--json").json()
    #expect(report["pausedUntil"] as? String == "2023-11-15T00:13:20Z")
    #expect(report["topics"] as? [String] == ["mine"])
  }

  // MARK: login-item

  @Test(arguments: [
    ("on", LoginItemPayload.Action.enable), ("off", .disable), ("status", .status),
  ])
  func loginItemSendsTheRightRequestAndLaunchesTheApp(
    word: String, action: LoginItemPayload.Action
  ) async throws {
    let state = LoginItemState.enabled
    let app = FakeApp()
    await app.reply(
      to: .loginItem,
      with: .success(
        id: "l", result: ResultPayload(loginItem: LoginItemResult(state: state.rawValue))))
    let result = await CLIRig(app: app).run("login-item", word, "--json")
    #expect(result.exit == .success)
    let report = try result.json()
    #expect(report["state"] as? String == state.rawValue)
    #expect(report["enabled"] as? Bool == state.isEnabled)
    let call = try #require(await app.calls.first)
    #expect(call.request.command == .loginItem)
    #expect(call.request.loginItem?.action == action)
    #expect(call.launch)
  }

  @Test(arguments: LoginItemState.allCases)
  func everyStateHasAHumanLine(state: LoginItemState) async {
    let app = FakeApp()
    await app.reply(
      to: .loginItem,
      with: .success(
        id: "l", result: ResultPayload(loginItem: LoginItemResult(state: state.rawValue))))
    let result = await CLIRig(app: app).run("login-item", "status")
    #expect(result.exit == .success)
    #expect(!result.stdout.isEmpty)
  }

  @Test func loginItemWithTheAppUnreachableIsExitFour() async {
    let rig = CLIRig(app: FakeApp(failure: .appUnavailable))
    #expect(await rig.run("login-item", "on").exit == .appUnavailable)
  }

  @Test func anUnknownActionIsAUsageError() async {
    #expect(await CLIRig().run("login-item", "maybe").exit == .usage)
    #expect(await CLIRig().run("login-item").exit == .usage)
  }

  // MARK: doctor and uninstall

  @Test func doctorReportsTheLoginItemAsAWarningNeverAFailure() async throws {
    let app = FakeApp()
    await app.reply(
      to: .loginItem,
      with: .success(
        id: "l", result: ResultPayload(loginItem: LoginItemResult(state: "notRegistered"))))
    let result = await CLIRig(app: app).run("doctor", "--json")
    #expect(result.exit == .success)
    let checks = try #require(try result.json()["checks"] as? [[String: Any]])
    let item = try #require(checks.first { $0["name"] as? String == "login-item" })
    #expect(item["status"] as? String == "warn")
    #expect(item["detail"] as? String == "Enable with: ntfy-mac login-item on")
  }

  @Test func doctorSkipsTheLoginItemWhenTheAppIsDown() async throws {
    let result = await CLIRig(app: FakeApp(failure: .appUnavailable)).run("doctor", "--json")
    let checks = try #require(try result.json()["checks"] as? [[String: Any]])
    let item = try #require(checks.first { $0["name"] as? String == "login-item" })
    #expect(item["status"] as? String == "skipped")
  }

  @Test func uninstallRemovesTheLoginItemThroughARunningApp() async throws {
    let app = FakeApp()
    let rig = CLIRig(app: app)
    let result = await rig.run("uninstall", "--yes", "--json")
    #expect(result.exit == .success)
    let removed = try #require(try result.json()["removed"] as? [String])
    #expect(removed.contains("login item"))
    let actions = await app.calls.compactMap { $0.request.loginItem?.action }
    #expect(actions.contains(.disable))
    #expect(await app.calls.allSatisfy { !$0.launch })
  }

  @Test func uninstallWithoutARunningAppStillSucceeds() async {
    let rig = CLIRig(app: FakeApp(failure: .appUnavailable))
    #expect(await rig.run("uninstall", "--yes").exit == .success)
  }
}
