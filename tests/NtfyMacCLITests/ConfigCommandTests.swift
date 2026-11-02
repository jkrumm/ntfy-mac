import Foundation
import NtfyCore
import Testing

@testable import NtfyMacCLI

@Suite struct ConfigCommandTests {
  @Test func overviewListsAllPrioritiesWithDefaults() async {
    let result = await CLIRig().run("config")
    #expect(result.exit == .success)
    #expect(result.stdout.contains("5 (urgent)    Ping          never"))
    #expect(result.stdout.contains("3 (default)   Pop           8s"))
    #expect(result.stdout.contains("1 (min)       Tink          4s"))
  }

  @Test func settingASoundPersistsAndMarksItCustom() async {
    let rig = CLIRig()
    let result = await rig.run("config", "sounds", "set", "5", "Sosumi")
    #expect(result.exit == .success)
    #expect(result.stdout.contains("Priority 5 (urgent) → Sosumi"))
    #expect(await rig.config.load().sounds == [5: .named("Sosumi")])
    #expect(await rig.run("config", "sounds").stdout.contains("Sosumi        custom"))
  }

  @Test func silentIsStoredAsNull() async {
    let rig = CLIRig()
    _ = await rig.run("config", "sounds", "set", "2", "silent")
    #expect(await rig.config.load().sounds == [2: .silent])
  }

  @Test func anUnknownSoundIsAUsageError() async {
    let rig = CLIRig()
    let result = await rig.run("config", "sounds", "set", "5", "Nope")
    #expect(result.exit == .usage)
    #expect(result.stderr.contains("Unknown sound: Nope"))
    #expect(await rig.config.load().sounds.isEmpty)
  }

  @Test(arguments: ["0", "6", "-1", "x"])
  func aPriorityOutsideOneToFiveIsAUsageError(priority: String) async {
    let result = await CLIRig().run("config", "sounds", "set", priority, "Pop")
    #expect(result.exit == .usage)
  }

  @Test func dismissAcceptsSecondsAndNever() async {
    let rig = CLIRig()
    #expect(await rig.run("config", "dismiss", "set", "3", "15").exit == .success)
    #expect(await rig.run("config", "dismiss", "set", "5", "never").exit == .success)
    #expect(await rig.config.load().dismiss == [3: 15, 5: 0])
    let shown = await rig.run("config", "dismiss").stdout
    #expect(shown.contains("3 (default)   15s           custom"))
    #expect(shown.contains("5 (urgent)    never         custom"))
  }

  @Test(arguments: ["soon", "-5", "nan", "inf"])
  func aBadDismissValueIsAUsageError(value: String) async {
    let result = await CLIRig().run("config", "dismiss", "set", "3", value)
    #expect(result.exit == .usage)
  }

  @Test func resetClearsOnlyItsOwnSection() async {
    let rig = CLIRig()
    _ = await rig.run("config", "sounds", "set", "5", "Sosumi")
    _ = await rig.run("config", "dismiss", "set", "3", "15")
    let result = await rig.run("config", "sounds", "reset")
    #expect(result.stdout.contains("Sound configuration reset to defaults."))
    let config = await rig.config.load()
    #expect(config.sounds.isEmpty)
    #expect(config.dismiss == [3: 15])
    _ = await rig.run("config", "dismiss", "reset")
    #expect(await rig.config.load().dismiss.isEmpty)
  }

  @Test func listIncludesSilentAndTheInstalledSounds() async throws {
    let result = await CLIRig().run("config", "sounds", "list", "--json")
    let sounds = try #require(try result.json()["sounds"] as? [String])
    #expect(sounds == ["Ping", "Pop", "Sosumi", "Tink", "silent"])
  }

  @Test func jsonReturnsTheTable() async throws {
    let result = await CLIRig().run("config", "--json")
    let rows = try #require(try result.json()["priorities"] as? [[String: Any]])
    #expect(rows.count == 5)
    #expect(rows.first?["priority"] as? Int == 5)
  }
}
