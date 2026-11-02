import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

@MainActor @Suite struct SettingsModelServerTests {
  @Test func theStoredTokenIsMaskedAndNeverReadIntoTheField() async {
    let rig = SettingsRig(token: "tk_secret")
    await rig.edit { $0.url = "https://ntfy.example.com" }
    await rig.model.reload()
    #expect(rig.model.hasStoredToken)
    #expect(rig.model.tokenText.isEmpty)
    #expect(rig.model.maskedTokenPlaceholder == "Saved in the Keychain")
    #expect(rig.model.urlText == "https://ntfy.example.com")
  }

  @Test func aPassingTestSavesTheURLToTheConfigAndTheTokenToTheKeychainOnly() async {
    let rig = SettingsRig(testResult: .ok(topics: ["alerts", "ops"]))
    rig.model.urlText = " ntfy.example.com/ "
    rig.model.tokenText = "tk_new"
    await rig.model.testAndSave()
    #expect(rig.model.serverTest == .finished(.ok(topics: ["alerts", "ops"])))
    #expect(await rig.secrets.token() == "tk_new")
    let config = await rig.current
    #expect(config.url == "https://ntfy.example.com")
    #expect(config.token == nil)
    #expect(rig.model.tokenText.isEmpty)
    #expect(rig.model.urlText == "https://ntfy.example.com")
    #expect(rig.model.serverTopics == ["alerts", "ops"])
    #expect(rig.model.hasStoredToken)
    let calls = await rig.tester.calls
    #expect(
      calls == [.init(url: "https://ntfy.example.com", token: "tk_new", allowInsecure: false)])
  }

  @Test func aFailingTestSavesNothing() async {
    let rig = SettingsRig(token: "tk_old", testResult: .unauthorized)
    await rig.edit { $0.url = "https://old.example.com" }
    await rig.model.reload()
    rig.model.urlText = "https://new.example.com"
    rig.model.tokenText = "tk_new"
    await rig.model.testAndSave()
    #expect(rig.model.serverTest == .finished(.unauthorized))
    #expect(await rig.secrets.token() == "tk_old")
    #expect(await rig.current.url == "https://old.example.com")
    #expect(rig.model.tokenText == "tk_new")
    #expect(rig.model.hasUnsavedServerChanges)
  }

  @Test func anEmptyTokenFieldTestsWithTheStoredToken() async {
    let rig = SettingsRig(token: "tk_stored", testResult: .ok(topics: []))
    rig.model.urlText = "https://new.example.com"
    await rig.model.testAndSave()
    let calls = await rig.tester.calls
    #expect(calls.map(\.token) == ["tk_stored"])
    #expect(await rig.secrets.token() == "tk_stored")
    #expect(await rig.current.url == "https://new.example.com")
  }

  @Test func withoutAnyTokenNothingIsTested() async {
    let rig = SettingsRig()
    rig.model.urlText = "https://new.example.com"
    await rig.model.testAndSave()
    guard case .finished(.invalid(let reason)) = rig.model.serverTest else {
      Issue.record("expected invalid, got \(rig.model.serverTest)")
      return
    }
    #expect(reason.contains("token"))
    #expect(await rig.tester.calls.isEmpty)
  }

  @Test func anUnusableAddressIsRefusedBeforeTheServerIsAsked() async {
    let rig = SettingsRig()
    rig.model.urlText = "ftp://x.example.com"
    rig.model.tokenText = "tk"
    await rig.model.testAndSave()
    #expect(
      rig.model.serverTest
        == .finished(.invalid(reason: "The server URL must be http or https (got ftp:).")))
    #expect(await rig.tester.calls.isEmpty)
  }

  @Test func theTestHonoursTheAllowInsecureSetting() async {
    let rig = SettingsRig()
    await rig.model.setAllowInsecure(true)
    rig.model.urlText = "http://nas.local:2586"
    rig.model.tokenText = "tk"
    await rig.model.testAndSave()
    #expect(await rig.tester.calls.map(\.allowInsecure) == [true])
    #expect(await rig.current.allowInsecure)
  }

  @Test func theLegacyPlaintextTokenIsScrubbedOnSave() async {
    let rig = SettingsRig()
    await rig.replace(Config(url: "https://old", token: "tk_legacy"))
    rig.model.urlText = "https://new.example.com"
    rig.model.tokenText = "tk"
    await rig.model.testAndSave()
    #expect(await rig.current.token == nil)
  }

  @Test(arguments: [
    ServerTestResult.unauthorized, .unreachable, .insecure, .redirected,
    .invalid(reason: "Because."), .ok(topics: []), .ok(topics: ["a"]), .ok(topics: ["a", "b"]),
  ])
  func everyResultHasAnActionableExplanation(result: ServerTestResult) {
    #expect(!result.explanation.isEmpty)
  }

  @Test func aConfigFileChangeOutsideTheAppShowsUpAndKeepsTypedText() async {
    let rig = SettingsRig()
    rig.model.start()
    #expect(await rig.eventually { rig.model.soundNames.count == 5 })
    rig.model.tokenText = "half typed"
    await rig.edit { $0.reAlertMaxRepeats = 3 }
    rig.configChanges.fire()
    #expect(await rig.eventually { rig.model.config.reAlertMaxRepeats == 3 })
    #expect(rig.model.tokenText == "half typed")
    rig.model.stop()
  }
}
