import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

@MainActor @Suite struct SettingsModelSettingsTests {
  // MARK: Presenting

  @Test func presentingLastsAnHourOnTheInjectedClock() async {
    let rig = SettingsRig()
    await rig.model.setPresenting(true)
    let stored = await rig.current.meeting.presentingUntil
    #expect(stored == rig.pipeline.clock.now().addingTimeInterval(3600))
    #expect(rig.model.isPresenting)
    rig.pipeline.clock.advance(by: .seconds(3601))
    #expect(!rig.model.isPresenting)
    await rig.model.setPresenting(false)
    #expect(await rig.current.meeting.presentingUntil == nil)
  }

  // MARK: Topics

  @Test func topicsListServerThenLocalThenSeenOnes() async throws {
    let rig = SettingsRig(serverTopics: ["zeta", "alpha"])
    await rig.edit {
      $0.url = "https://ntfy.example.com"
      $0.extraTopics = ["local"]
      $0.topicSettings["only-settings"] = TopicSettings(mute: true)
    }
    _ = try? await rig.pipeline.history.append(rig.pipeline.message("1", topic: "seen"))
    _ = try? await rig.pipeline.history.append(rig.pipeline.message("2", topic: "alpha"))
    rig.model.start()
    #expect(await rig.eventually { rig.model.topicRows.count == 5 })
    let rows = rig.model.topicRows
    #expect(rows.map(\.name) == ["zeta", "alpha", "local", "only-settings", "seen"])
    #expect(rows.map(\.origin) == [.server, .server, .local, .seen, .seen])
    #expect(rows[3].settings.mute)
    rig.model.stop()
  }

  @Test func subscribeAndUnsubscribeMirrorTheCommands() async {
    let rig = SettingsRig()
    #expect(await rig.model.subscribe("builds"))
    #expect(await rig.current.extraTopics == ["builds"])
    #expect(await !rig.model.subscribe("builds"))
    #expect(rig.model.notice?.contains("already") == true)
    #expect(await !rig.model.subscribe("not valid!"))
    #expect(rig.model.notice?.contains("Invalid topic name") == true)
    #expect(await !rig.model.unsubscribe("server-topic"))
    #expect(rig.model.notice?.contains("web app") == true)
    #expect(await rig.model.unsubscribe("builds"))
    #expect(await rig.current.extraTopics.isEmpty)
  }

  @Test func theTypedTopicIsClearedOnlyWhenItWasAdded() async {
    let rig = SettingsRig()
    rig.model.newTopicText = "builds"
    await rig.model.addTypedTopic()
    #expect(rig.model.newTopicText.isEmpty)
    rig.model.newTopicText = "bad topic"
    await rig.model.addTypedTopic()
    #expect(rig.model.newTopicText == "bad topic")
  }

  @Test func topicSettingsAreStoredLikeTheCommandAndPrunedAtTheDefaults() async {
    let rig = SettingsRig()
    await rig.model.setMute(true, topic: "builds")
    await rig.model.setMinPriority(9, topic: "builds")
    await rig.model.setEmoji("  🔨 ", topic: "builds")
    #expect(
      await rig.current.topicSettings["builds"]
        == TopicSettings(mute: true, minPriority: 5, emoji: "🔨"))
    await rig.model.setMute(false, topic: "builds")
    await rig.model.setMinPriority(nil, topic: "builds")
    await rig.model.setEmoji("   ", topic: "builds")
    #expect(await rig.current.topicSettings["builds"] == nil)
    await rig.model.setMute(true, topic: "other")
    await rig.model.resetTopic("other")
    #expect(await rig.current.topicSettings.isEmpty)
  }

  // MARK: Sounds and dismiss

  @Test func theEffectiveSoundAndDismissStartAtTheDefaults() {
    let model = SettingsRig().model
    #expect(model.soundChoice(for: 5) == .named("Ping"))
    #expect(model.soundChoice(for: 3) == .named("Pop"))
    #expect(model.dismissSeconds(for: 3) == 8)
    #expect(model.dismissSeconds(for: 5) == nil)
    #expect(!model.isCustomized(3))
  }

  @Test func soundsAndDismissAreSetAndResetPerRowAndOverall() async {
    let rig = SettingsRig()
    await rig.model.setSound(.named("Glass"), for: 5)
    await rig.model.setSound(.silent, for: 1)
    await rig.model.setDismiss(seconds: nil, for: 3)
    await rig.model.setDismiss(seconds: 0.2, for: 4)
    let config = await rig.current
    #expect(config.sounds == [5: .named("Glass"), 1: .silent])
    #expect(config.dismiss == [3: 0, 4: 1])
    #expect(rig.model.soundChoice(for: 1) == .silent)
    #expect(rig.model.dismissSeconds(for: 3) == nil)
    #expect(rig.model.isCustomized(5) && rig.model.isCustomized(3))
    await rig.model.resetPriority(5)
    #expect(await rig.current.sounds == [1: .silent])
    await rig.model.resetSoundsAndDismiss()
    let reset = await rig.current
    #expect(reset.sounds.isEmpty && reset.dismiss.isEmpty)
  }

  @Test func previewPlaysTheEffectiveSoundAndNothingForSilent() async {
    let rig = SettingsRig()
    rig.model.previewSound(for: 5)
    await rig.model.setSound(.named("Sosumi"), for: 5)
    rig.model.previewSound(for: 5)
    await rig.model.setSound(.silent, for: 5)
    rig.model.previewSound(for: 5)
    #expect(rig.preview.played == ["Ping", "Sosumi"])
  }

  @Test func aRemovedCustomSoundStaysInThePicker() async {
    let rig = SettingsRig()
    await rig.model.reload()
    await rig.model.setSound(.named("Gone"), for: 2)
    #expect(rig.model.soundOptions(for: 2).contains("Gone"))
    #expect(!rig.model.soundOptions(for: 3).contains("Gone"))
  }

  // MARK: Re-alert and quiet hours

  @Test func reAlertValuesFollowTheCommandRules() async {
    let rig = SettingsRig()
    await rig.model.setReAlert(false)
    await rig.model.setReAlertInterval(seconds: 600)
    await rig.model.setReAlertMinPriority(9)
    await rig.model.setReAlertMaxRepeats(0)
    let config = await rig.current
    #expect(!config.reAlert)
    #expect(config.reAlertIntervalSeconds == 600)
    #expect(config.reAlertMinPriority == 5)
    #expect(config.reAlertMaxRepeats == 0)
    await rig.model.setReAlertInterval(seconds: 0)
    #expect(rig.model.notice != nil)
    await rig.model.setReAlertMaxRepeats(-1)
    #expect(await rig.current.reAlertIntervalSeconds == 600)
    #expect(await rig.current.reAlertMaxRepeats == 0)
  }

  @Test func quietHoursRefuseAnEmptyWindow() async throws {
    let rig = SettingsRig()
    let ten = try #require(ClockTime(hour: 10, minute: 0))
    await rig.model.setQuietHoursStart(ten)
    await rig.model.setQuietHoursEnabled(true)
    await rig.model.setUrgentBypass(false)
    await rig.model.setDigest(false)
    let quiet = await rig.current.quietHours
    #expect(quiet == QuietHours(enabled: true, start: ten, urgentBypass: false, digest: false))
    await rig.model.setQuietHoursEnd(ten)
    #expect(rig.model.notice != nil)
    #expect(await rig.current.quietHours.end == QuietHours.defaultEnd)
  }

  @Test func timePickersRoundTripThroughDates() throws {
    let model = SettingsRig().model
    let time = try #require(ClockTime(hour: 22, minute: 30))
    #expect(model.clockTime(from: model.date(for: time)) == time)
  }

  // MARK: Actions and general

  @Test func privateNetworkActionsAreStored() async {
    let rig = SettingsRig()
    await rig.model.setAllowPrivateNetworkActions(true)
    #expect(await rig.current.allowPrivateNetworkActions)
  }

  @Test func theLoginItemGoesThroughThePort() async {
    let rig = SettingsRig(loginItem: InMemoryLoginItem(requiresApproval: true))
    await rig.model.setLaunchAtLogin(true)
    #expect(rig.model.loginItem == .requiresApproval)
    #expect(rig.model.loginItemNote?.contains("Login Items") == true)
    await rig.model.setLaunchAtLogin(false)
    #expect(rig.model.loginItem == .notRegistered)
    #expect(rig.model.loginItemNote == nil)
    #expect(await rig.current == Config())
  }

  @Test func resumeEndsThePause() async {
    let rig = SettingsRig()
    await rig.edit { $0.pausedUntil = Date.distantFuture }
    await rig.model.resume()
    #expect(await rig.current.pausedUntil == nil)
  }

  @Test func setUpAgainAsksTheRouterForTheOnboarding() {
    let rig = SettingsRig()
    rig.model.setUpAgain()
    #expect(rig.windows.request?.window == .onboarding)
  }
}
