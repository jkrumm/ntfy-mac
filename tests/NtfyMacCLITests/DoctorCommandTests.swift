import Foundation
import NtfyCore
import NtfyIPC
import Testing

@testable import NtfyMacCLI

@Suite struct DoctorCommandTests {
  private func checks(_ result: RunResult) throws -> [String: String] {
    let list = try #require(try result.json()["checks"] as? [[String: Any]])
    return Dictionary(
      uniqueKeysWithValues: list.compactMap { check -> (String, String)? in
        guard let name = check["name"] as? String, let status = check["status"] as? String
        else { return nil }
        return (name, status)
      })
  }

  @Test func aHealthyInstallPassesWithTheDocumentedShape() async throws {
    let result = await CLIRig().run("doctor", "--json")
    #expect(result.exit == .success)
    let report = try result.json()
    #expect(report["ok"] as? Bool == true)
    #expect(report["version"] as? String == Version.current)
    #expect(report["installChannel"] as? String == "direct")
    let status = try checks(result)
    for name in [
      "config", "token", "server", "auth", "topics", "app", "permissions", "login-item", "update",
      "time-sensitive",
    ] {
      #expect(status[name] == "ok", "\(name)")
    }
  }

  @Test func theUpdateCheckSaysWhoUpdatesAndWhy() async throws {
    let signed = SigningInfo(teamID: "TEAM000001", hardenedRuntime: true, developerID: true)
    var rig = CLIRig()
    #expect(try checks(await rig.run("doctor", "--json"))["update"] == "ok")

    rig.signing = signed
    let active = await rig.run("doctor").stdout
    #expect(active.contains("Updates through the app"))
    #expect(active.contains("Developer ID: yes, Hardened runtime: yes, Team pin: not recorded"))

    rig.recordedTeam = "TEAM000002"
    let mismatch = await rig.run("doctor", "--json")
    #expect(try checks(mismatch)["update"] == "warn")
    #expect(mismatch.exit == .success)

    rig.recordedTeam = "TEAM000001"
    #expect(await rig.run("doctor").stdout.contains("Team pin: matches"))

    rig.executablePath = "/opt/homebrew/Cellar/ntfy-mac/2.0.0/NtfyMac.app/Contents/MacOS/ntfy-mac"
    #expect(await rig.run("doctor").stdout.contains("Old Homebrew formula copy"))
  }

  @Test func theTimeSensitiveCheckReadsTheSignedEntitlement() async throws {
    var rig = CLIRig()
    let adHoc = await rig.run("doctor")
    #expect(adHoc.stdout.contains("Not available in this build"))
    #expect(try checks(await rig.run("doctor", "--json"))["time-sensitive"] == "ok")

    rig.signing = SigningInfo(teamID: "TEAM000001", hardenedRuntime: true, developerID: true)
    let missing = await rig.run("doctor", "--json")
    #expect(try checks(missing)["time-sensitive"] == "warn")
    #expect(missing.exit == .success)

    rig.signing = SigningInfo(
      teamID: "TEAM000001", hardenedRuntime: true, developerID: true,
      entitlements: [.timeSensitiveNotifications])
    let present = await rig.run("doctor")
    #expect(present.stdout.contains("Time-sensitive notifications available"))
  }

  @Test func doctorIsReadOnly() async {
    let rig = CLIRig()
    let before = await rig.config.load()
    _ = await rig.run("doctor")
    _ = await rig.run("doctor", "--json")
    let commands = await rig.app.commands()
    #expect(!commands.contains(.notify))
    #expect(Set(commands) == [.status, .permission, .loginItem])
    #expect(await rig.app.calls.allSatisfy { !$0.launch })
    #expect(await rig.config.load() == before)
    #expect(await rig.secrets.token() == "tk_secret")
    #expect(await rig.processes.runs.isEmpty)
  }

  @Test func sendTestIsTheOnlyWayToPostANotification() async throws {
    let rig = CLIRig()
    let result = await rig.run("doctor", "--send-test", "--json")
    #expect(result.exit == .success)
    #expect(try checks(result)["test"] == "ok")
    #expect(await rig.app.commands().filter { $0 == .notify }.count == 1)
  }

  @Test func anAppThatIsDownFailsWithFourAndIsNeverLaunched() async throws {
    let rig = CLIRig(app: FakeApp(failure: .appUnavailable))
    let result = await rig.run("doctor", "--json")
    #expect(result.exit == .appUnavailable)
    #expect(try checks(result)["app"] == "fail")
    #expect(try checks(result)["permissions"] == "skipped")
    #expect(await rig.app.calls.allSatisfy { !$0.launch })
  }

  @Test func aBadTokenFailsWithThree() async throws {
    let result = await CLIRig(topicFailure: .unauthorized).run("doctor", "--json")
    #expect(result.exit == .auth)
    let status = try checks(result)
    #expect(status["server"] == "ok")
    #expect(status["auth"] == "fail")
  }

  @Test func anUnreachableServerFailsWithSeven() async throws {
    let result = await CLIRig(topicFailure: .serverUnreachable).run("doctor", "--json")
    #expect(result.exit == .serverUnreachable)
    #expect(try checks(result)["server"] == "fail")
  }

  @Test func deniedNotificationsFailWithFour() async throws {
    let app = FakeApp()
    let denied = PermissionSummary(
      usable: false, problems: [PermissionIssue(code: "denied", hint: "Allow notifications")])
    await app.reply(
      to: .permission, with: .success(id: "x", result: ResultPayload(permission: denied)))
    let result = await CLIRig(app: app).run("doctor", "--json")
    #expect(result.exit == .appUnavailable)
    #expect(try checks(result)["permissions"] == "fail")
  }

  @Test func anUnconfiguredInstallFailsAndSkipsTheServerChecks() async throws {
    let result = await CLIRig(configured: false).run("doctor", "--json")
    #expect(result.exit != .success)
    let status = try checks(result)
    #expect(status["config"] == "fail")
    #expect(status["token"] == "fail")
    #expect(status["server"] == "skipped")
  }

  @Test func theLegacyPlaintextTokenIsAWarningNotAFailure() async throws {
    let rig = CLIRig(configured: false)
    await rig.config.save(Config(url: CLIRig.serverURL, token: "tk_old"))
    let result = await rig.run("doctor", "--json")
    #expect(result.exit == .success)
    #expect(try checks(result)["token"] == "warn")
  }

  @Test func textModeShowsTheVerdict() async {
    let result = await CLIRig().run("doctor")
    #expect(result.stdout.contains("ntfy-mac doctor ("))
    #expect(
      result.stdout.contains("Everything looks good.") || result.stdout.contains("suggestion"))
  }
}
