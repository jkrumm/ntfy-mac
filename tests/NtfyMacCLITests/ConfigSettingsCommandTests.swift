import Foundation
import NtfyCore
import Testing

@testable import NtfyMacCLI

@Suite struct ConfigSettingsCommandTests {
  /// A rig whose config holds a key this version does not know.
  private func rigWithUnknownKey() async -> CLIRig {
    let rig = CLIRig()
    await rig.config.update { $0.extras = ["future": .string("kept")] }
    return rig
  }

  private func expectExtrasKept(_ rig: CLIRig) async throws {
    let config = await rig.config.load()
    #expect(config.extras["future"] == .string("kept"))
    let reread = try #require(Config.parse(try config.serialized()))
    #expect(reread == config)
  }

  // MARK: get, set, reset

  @Test func getPrintsTheDefaultAndSetChangesIt() async throws {
    let rig = await rigWithUnknownKey()
    let before = await rig.run("config", "get", "reAlertIntervalSeconds")
    #expect(before.stdout == "reAlertIntervalSeconds = 300 (default)\n")
    let set = await rig.run("config", "set", "reAlertIntervalSeconds", "600")
    #expect(set.exit == .success)
    #expect(set.stdout == "reAlertIntervalSeconds = 600\n")
    #expect(await rig.config.load().reAlertIntervalSeconds == 600)
    try await expectExtrasKept(rig)
  }

  @Test(arguments: ["true", "on", "TRUE"])
  func booleansAcceptTrueAndOn(value: String) async {
    let rig = CLIRig()
    #expect(await rig.run("config", "set", "allowInsecure", value).exit == .success)
    #expect(await rig.config.load().allowInsecure)
  }

  @Test func booleansAcceptFalseAndOff() async {
    let rig = CLIRig()
    #expect(await rig.run("config", "set", "reAlert", "off").exit == .success)
    #expect(await rig.config.load().reAlert == false)
    #expect(await rig.run("config", "set", "reAlert", "false").exit == .success)
    #expect(await rig.run("config", "set", "reAlert", "on").exit == .success)
    #expect(await rig.config.load().reAlert)
  }

  @Test func everyKeyHasATypedRoundTrip() async {
    struct Case {
      let key: String
      let value: String
      let check: @Sendable (Config) -> Bool
    }
    let cases = [
      Case(key: "allowInsecure", value: "true", check: { $0.allowInsecure }),
      Case(
        key: "allowPrivateNetworkActions", value: "on", check: { $0.allowPrivateNetworkActions }),
      Case(key: "reAlert", value: "off", check: { !$0.reAlert }),
      Case(key: "reAlertIntervalSeconds", value: "45", check: { $0.reAlertIntervalSeconds == 45 }),
      Case(key: "reAlertMinPriority", value: "4", check: { $0.reAlertMinPriority == 4 }),
      Case(key: "reAlertMaxRepeats", value: "0", check: { $0.reAlertMaxRepeats == 0 }),
    ]
    for entry in cases {
      let (key, value, check) = (entry.key, entry.value, entry.check)
      let rig = CLIRig()
      #expect(await rig.run("config", "set", key, value).exit == .success, "\(key)")
      #expect(check(await rig.config.load()), "\(key)")
      #expect(await rig.run("config", "reset", key).exit == .success, "\(key)")
      #expect(await rig.config.load() == Config(url: CLIRig.serverURL), "\(key) reset")
    }
  }

  @Test(arguments: [
    ("allowInsecure", "maybe"), ("reAlert", "1"), ("reAlertIntervalSeconds", "0"),
    ("reAlertIntervalSeconds", "soon"), ("reAlertMinPriority", "6"),
    ("reAlertMinPriority", "0"), ("reAlertMaxRepeats", "-1"), ("reAlertMaxRepeats", "1.5"),
    ("nonsense", "1"),
  ])
  func invalidInputIsAUsageErrorAndChangesNothing(key: String, value: String) async {
    let rig = CLIRig()
    let result = await rig.run("config", "set", key, value)
    #expect(result.exit == .usage)
    #expect(await rig.config.load() == Config(url: CLIRig.serverURL))
  }

  @Test func scalarJSONNamesKeyValueAndDefault() async throws {
    let rig = CLIRig()
    let json = try await rig.run("config", "set", "reAlertMinPriority", "4", "--json").json()
    #expect(json["key"] as? String == "reAlertMinPriority")
    #expect(json["value"] as? Int == 4)
    #expect(json["isDefault"] as? Bool == false)
    let flag = try await rig.run("config", "get", "reAlert", "--json").json()
    #expect(flag["value"] as? Bool == true)
    #expect(flag["isDefault"] as? Bool == true)
  }

  @Test func aUsageErrorInJSONModeIsTheEnvelope() async throws {
    let result = await CLIRig().run("config", "set", "reAlert", "maybe", "--json")
    #expect(result.exit == .usage)
    let error = try #require(try result.json()["error"] as? [String: Any])
    #expect(error["code"] as? String == "usage")
    #expect(error["exitCode"] as? Int == 2)
  }

  // MARK: show

  @Test func showListsScalarsTopicsAndQuietHours() async throws {
    let rig = CLIRig()
    _ = await rig.run("config", "topic", "set", "builds", "--mute")
    _ = await rig.run("config", "quiet-hours", "set")
    _ = await rig.run("config", "set", "reAlert", "off")
    let text = await rig.run("config", "show").stdout
    #expect(text.contains("reAlert = false"))
    #expect(text.contains("builds: muted"))
    #expect(text.contains("Quiet hours: on"))
    let json = try await rig.run("config", "show", "--json").json()
    #expect((json["priorities"] as? [Any])?.count == 5)
    #expect((json["settings"] as? [[String: Any]])?.count == ConfigKey.allCases.count)
    #expect((json["topics"] as? [[String: Any]])?.first?["topic"] as? String == "builds")
    #expect((json["quietHours"] as? [String: Any])?["enabled"] as? Bool == true)
    #expect(await rig.run("config", "--json").stdout == rig.run("config", "show", "--json").stdout)
  }

  // MARK: topics

  @Test func topicSetMutesFiltersAndDecorates() async throws {
    let rig = await rigWithUnknownKey()
    let result = await rig.run(
      "config", "topic", "set", "builds", "--mute", "--min-priority", "4", "--emoji", "🔨")
    #expect(result.exit == .success)
    #expect(
      await rig.config.load().topicSettings["builds"]
        == TopicSettings(mute: true, minPriority: 4, emoji: "🔨"))
    #expect(result.stdout == "builds: muted, minimum priority 4, emoji 🔨\n")
    try await expectExtrasKept(rig)
  }

  @Test func topicSetKeepsWhatYouDidNotTouchAndNoneClears() async {
    let rig = CLIRig()
    _ = await rig.run("config", "topic", "set", "builds", "--mute", "--min-priority", "3")
    _ = await rig.run("config", "topic", "set", "builds", "--unmute")
    #expect(
      await rig.config.load().topicSettings["builds"] == TopicSettings(minPriority: 3))
    _ = await rig.run("config", "topic", "set", "builds", "--min-priority", "none")
    #expect(await rig.config.load().topicSettings["builds"] == nil)
    _ = await rig.run("config", "topic", "set", "builds", "--emoji", "🔨")
    _ = await rig.run("config", "topic", "set", "builds", "--emoji", "none")
    #expect(await rig.config.load().topicSettings.isEmpty)
  }

  @Test func topicShowListAndResetAndJSON() async throws {
    let rig = CLIRig()
    #expect(await rig.run("config", "topic", "list").stdout.contains("No topic has its own"))
    _ = await rig.run("config", "topic", "set", "b-topic", "--mute")
    _ = await rig.run("config", "topic", "set", "a_topic", "--emoji", "🔔")
    let list = try await rig.run("config", "topic", "list", "--json").json()
    let topics = try #require(list["topics"] as? [[String: Any]])
    #expect(topics.compactMap { $0["topic"] as? String } == ["a_topic", "b-topic"])
    let shown = try await rig.run("config", "topic", "show", "b-topic", "--json").json()
    #expect(shown["mute"] as? Bool == true)
    #expect(shown["minPriority"] == nil)
    let plain = await rig.run("config", "topic", "show", "unknown")
    #expect(plain.stdout == "unknown: notifying, minimum priority none, emoji none\n")
    _ = await rig.run("config", "topic", "reset", "b-topic")
    #expect(Set(await rig.config.load().topicSettings.keys) == ["a_topic"])
    #expect(await rig.run("config", "topic").stdout.contains("a_topic"))
  }

  @Test(arguments: [
    ["set", "builds"], ["set", "builds", "--mute", "--unmute"],
    ["set", "builds", "--min-priority", "9"], ["set", "builds", "--min-priority", "x"],
    ["set", "builds", "--emoji", " "], ["set", "bad topic", "--mute"], ["show", "a/b"],
    ["reset", ""],
  ])
  func invalidTopicInputIsAUsageError(arguments: [String]) async {
    let rig = CLIRig()
    let result = await rig.run(["config", "topic"] + arguments)
    #expect(result.exit == .usage)
    #expect(await rig.config.load().topicSettings.isEmpty)
  }

  // MARK: quiet hours

  @Test func quietHoursSetEnablesAndOffKeepsTheTimes() async throws {
    let rig = await rigWithUnknownKey()
    let set = await rig.run(
      "config", "quiet-hours", "set", "--start", "23:30", "--end", "06:15", "--no-urgent-bypass",
      "--no-digest")
    #expect(set.exit == .success)
    let expected = QuietHours(
      enabled: true, start: try #require(ClockTime("23:30")), end: try #require(ClockTime("06:15")),
      urgentBypass: false, digest: false)
    #expect(await rig.config.load().quietHours == expected)
    #expect(set.stdout.contains("Window:        23:30 to 06:15"))
    let off = await rig.run("config", "quiet-hours", "off")
    #expect(off.exit == .success)
    var disabled = expected
    disabled.enabled = false
    #expect(await rig.config.load().quietHours == disabled)
    try await expectExtrasKept(rig)
  }

  @Test func quietHoursSetWithoutOptionsEnablesTheDefaultsAndKeepsEarlierValues() async throws {
    let rig = CLIRig()
    _ = await rig.run("config", "quiet-hours", "set")
    #expect(await rig.config.load().quietHours == QuietHours(enabled: true))
    _ = await rig.run("config", "quiet-hours", "set", "--end", "08:00", "--no-digest")
    _ = await rig.run("config", "quiet-hours", "set", "--urgent-bypass", "--digest")
    let quiet = await rig.config.load().quietHours
    #expect(quiet.end.description == "08:00")
    #expect(quiet.start == QuietHours.defaultStart)
    #expect(quiet.digest && quiet.urgentBypass)
  }

  @Test func quietHoursJSONAndShow() async throws {
    let rig = CLIRig()
    let off = try await rig.run("config", "quiet-hours", "show", "--json").json()
    #expect(off["enabled"] as? Bool == false)
    #expect(off["start"] as? String == "22:00")
    #expect(off["end"] as? String == "07:00")
    let set = try await rig.run("config", "quiet-hours", "set", "--json").json()
    #expect(set["enabled"] as? Bool == true)
    #expect(await rig.run("config", "quiet-hours").stdout.contains("Quiet hours: on"))
  }

  @Test(arguments: [
    ["--start", "7:00"], ["--start", "24:00"], ["--end", "07:60"], ["--start", "noon"],
    ["--start", "08:00", "--end", "08:00"], ["--end", "22:00"],
    ["--urgent-bypass", "--no-urgent-bypass"], ["--digest", "--no-digest"],
  ])
  func invalidQuietHoursInputIsAUsageErrorAndChangesNothing(arguments: [String]) async {
    let rig = CLIRig()
    let result = await rig.run(["config", "quiet-hours", "set"] + arguments)
    #expect(result.exit == .usage)
    #expect(await rig.config.load().quietHours == QuietHours())
  }
}
