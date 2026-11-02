import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyPlatform
import NtfyTesting
import Testing

/// What the exposure tests share, outside the main actor so `@Test(arguments:)` can read it.
private enum Exposure {
  /// A file with keys this version does not know, which every edit must leave alone.
  static let base = """
    {
      "url": "https://old.example.com",
      "futureKey": {"nested": [1, 2, {"deep": true}]},
      "anotherFutureKey": "kept",
      "extraTopics": ["builds"],
      "pausedUntil": "2099-01-01T00:00:00.000Z"
    }
    """

  struct Change: Sendable {
    let apply: @MainActor (SettingsModel) async -> Void
    /// The value the catalog's key holds afterwards; nil for settings that live outside the file.
    let verify: @Sendable (Config) -> Bool
    /// The change removes its key instead of writing a value (the list or the pause is empty).
    var clearsKey = false
  }

  static let changes: [SettingID: Change] = [
    .serverURL: Change(
      apply: {
        $0.urlText = "https://new.example.com"
        $0.tokenText = "tk_new"
        await $0.testAndSave()
      }, verify: { $0.url == "https://new.example.com" && $0.token == nil }),
    .token: Change(
      apply: {
        $0.tokenText = "tk_new"
        await $0.testAndSave()
      }, verify: { $0.token == nil }),
    .allowInsecure: Change(
      apply: { await $0.setAllowInsecure(true) }, verify: { $0.allowInsecure }),
    .topicSubscribe: Change(
      apply: { _ = await $0.subscribe("ops") }, verify: { $0.extraTopics == ["builds", "ops"] }),
    .topicUnsubscribe: Change(
      apply: { _ = await $0.unsubscribe("builds") }, verify: { $0.extraTopics.isEmpty },
      clearsKey: true),
    .topicMute: Change(
      apply: { await $0.setMute(true, topic: "builds") },
      verify: { $0.topicSettings["builds"]?.mute == true }),
    .topicMinPriority: Change(
      apply: { await $0.setMinPriority(4, topic: "builds") },
      verify: { $0.topicSettings["builds"]?.minPriority == 4 }),
    .topicEmoji: Change(
      apply: { await $0.setEmoji("🔨", topic: "builds") },
      verify: { $0.topicSettings["builds"]?.emoji == "🔨" }),
    .sounds: Change(
      apply: { await $0.setSound(.named("Glass"), for: 5) },
      verify: { $0.sounds == [5: .named("Glass")] }),
    .dismiss: Change(
      apply: { await $0.setDismiss(seconds: 15, for: 3) }, verify: { $0.dismiss == [3: 15] }),
    .quietHoursEnabled: Change(
      apply: { await $0.setQuietHoursEnabled(true) }, verify: { $0.quietHours.enabled }),
    .quietHoursStart: Change(
      apply: { await $0.setQuietHoursStart(Exposure.time(9, 30)) },
      verify: { $0.quietHours.start == Exposure.time(9, 30) }),
    .quietHoursEnd: Change(
      apply: { await $0.setQuietHoursEnd(Exposure.time(6, 45)) },
      verify: { $0.quietHours.end == Exposure.time(6, 45) }),
    .quietHoursUrgentBypass: Change(
      apply: { await $0.setUrgentBypass(false) }, verify: { !$0.quietHours.urgentBypass }),
    .quietHoursDigest: Change(
      apply: { await $0.setDigest(false) }, verify: { !$0.quietHours.digest }),
    .reAlert: Change(apply: { await $0.setReAlert(false) }, verify: { !$0.reAlert }),
    .reAlertIntervalSeconds: Change(
      apply: { await $0.setReAlertInterval(seconds: 600) },
      verify: { $0.reAlertIntervalSeconds == 600 }),
    .reAlertMinPriority: Change(
      apply: { await $0.setReAlertMinPriority(4) }, verify: { $0.reAlertMinPriority == 4 }),
    .reAlertMaxRepeats: Change(
      apply: { await $0.setReAlertMaxRepeats(6) }, verify: { $0.reAlertMaxRepeats == 6 }),
    .allowPrivateNetworkActions: Change(
      apply: { await $0.setAllowPrivateNetworkActions(true) },
      verify: { $0.allowPrivateNetworkActions }),
    .meetingMode: Change(
      apply: { await $0.setMeetingMode(.pause) }, verify: { $0.meeting.mode == .pause }),
    .meetingUrgentBypass: Change(
      apply: { await $0.setMeetingUrgentBypass(false) }, verify: { !$0.meeting.urgentBypass }),
    .presenting: Change(
      apply: { await $0.setPresenting(true) },
      verify: { $0.meeting.presentingUntil.map { !PauseWindow.isIndefinite($0) } == true }),
    .loginItem: Change(apply: { await $0.setLaunchAtLogin(true) }, verify: { _ in true }),
    .pause: Change(
      apply: { await $0.resume() }, verify: { $0.pausedUntil == nil }, clearsKey: true),
  ]

  static func time(_ hour: Int, _ minute: Int) -> ClockTime {
    guard let time = ClockTime(hour: hour, minute: minute) else {
      preconditionFailure("not a time of day")
    }
    return time
  }
}

/// The parity guarantee for the Settings window: everything it shows is a catalog row, and
/// changing each setting through the model writes exactly the config key the catalog names, in
/// the same file the CLI edits.
@MainActor @Suite struct SettingsExposureTests {
  /// Catalog entries the window shows differently: the sound picker's options, a preview button
  /// and the notification permission status.
  private static let shownDifferently: Set<SettingID> = [
    .soundList, .soundPreview, .notificationPermission,
  ]

  private func rig(_ scratch: SettingsScratch) throws -> SettingsRig {
    try scratch.write(Exposure.base)
    let rig = SettingsRig(
      store: FileConfigStore(url: scratch.file), token: "tk_old",
      testResult: .ok(topics: ["alerts"]))
    return rig
  }

  /// The value at a catalog key such as `topicSettings.<topic>.mute`, with `<topic>` filled in.
  private func value(at key: String, in object: [String: ConfigValue]) -> ConfigValue? {
    var current: ConfigValue? = .object(object)
    for part in key.split(separator: ".") {
      let name = part == "<topic>" ? "builds" : String(part)
      current = current?.objectValue?[name]
    }
    return current
  }

  @Test func theWindowShowsEveryCatalogEntryExceptTheOnesItShowsDifferently() {
    let exposed = SettingsRig().model.exposedSettings
    #expect(Set(exposed).count == exposed.count, "a setting appears in two sections")
    let expected = Set(SettingsCatalog.entries.map(\.id)).subtracting(Self.shownDifferently)
    #expect(Set(exposed) == expected)
    for id in Self.shownDifferently {
      #expect(
        SettingsCatalog.entry(id).kind != .settable, "\(id) is settable, the window must edit it")
    }
    for id in exposed {
      #expect(SettingsCatalog.entry(id).id == id)
    }
  }

  @Test func everyExposedSettingHasAChangeThatIsCheckedBelow() {
    let exposed = SettingsRig().model.exposedSettings
    #expect(Set(Exposure.changes.keys) == Set(exposed))
  }

  @Test(arguments: Array(Exposure.changes.keys).sorted { $0.rawValue < $1.rawValue })
  func changingASettingWritesExactlyTheCatalogKeyAndKeepsUnknownKeys(id: SettingID) async throws {
    let scratch = SettingsScratch()
    let rig = try rig(scratch)
    let change = try #require(Exposure.changes[id])
    let entry = SettingsCatalog.entry(id)
    let before = try scratch.object()
    await rig.model.reload()

    await change.apply(rig.model)

    let after = try scratch.object()
    let changed = Set(before.keys).union(after.keys).filter { before[$0] != after[$0] }
    switch entry.storage {
    case .config:
      #expect(changed == [try #require(entry.topLevelKey)], "\(id): \(changed)")
      let key = try #require(entry.configKey)
      #expect((value(at: key, in: after) == nil) == change.clearsKey, "\(id): \(key)")
    case .keychain, .system:
      #expect(changed.isEmpty, "\(id): \(changed)")
    }
    let stored = try #require(Config.parse(Data(contentsOf: scratch.file)))
    #expect(change.verify(stored), "\(id): the file holds \(after)")
    for key in ["futureKey", "anotherFutureKey"] {
      #expect(after[key] == before[key], "\(id) lost \(key)")
    }
    #expect(after["token"] == nil, "\(id) wrote a token to the file")
  }

  @Test func theKeychainAndTheLoginItemHoldTheirOwnSettings() async throws {
    let scratch = SettingsScratch()
    let rig = try rig(scratch)
    await rig.model.reload()
    rig.model.tokenText = "tk_new"
    await rig.model.testAndSave()
    #expect(await rig.secrets.token() == "tk_new")
    await rig.model.setLaunchAtLogin(true)
    #expect(rig.loginItem.state() == .enabled)
    #expect(try scratch.object()["token"] == nil)
  }

  @Test func theModelAgreesWithConfigAfterTheRoundTrip() async throws {
    let scratch = SettingsScratch()
    let rig = try rig(scratch)
    await rig.model.setReAlertInterval(seconds: 90)
    await rig.model.setMute(true, topic: "builds")
    await rig.model.setQuietHoursStart(Exposure.time(23, 0))
    let stored = try #require(Config.parse(Data(contentsOf: scratch.file)))
    #expect(rig.model.config == stored)
  }
}
