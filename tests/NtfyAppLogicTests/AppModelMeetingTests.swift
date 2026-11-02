import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyIPC
import NtfyTesting
import Testing

private actor UnwritableConfigStore: ConfigStore {
  func load() -> Config { Config() }
  func save(_ config: Config) throws(NtfyError) { throw .storage("read-only") }
  func update(_ change: @Sendable (inout Config) -> Void) throws(NtfyError) {
    throw .storage("read-only")
  }
}

@MainActor @Suite struct AppModelMeetingTests {
  @MainActor private struct Rig {
    let pipeline: PipelineFixture
    let provider = ManualMeetingState()
    let model: AppModel

    init(mode: MeetingMode = .pause) {
      pipeline = PipelineFixture(config: Config(meeting: MeetingSettings(mode: mode)))
      let source = ManualPipelineSource()
      source.set(pipeline.handles)
      model = AppModel(
        source: source, meeting: provider, config: pipeline.config,
        permissions: InMemoryNotificationPermission(.allowed),
        clock: pipeline.clock, configChanges: { AsyncStream { $0.finish() } })
    }

    func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
      for _ in 0..<200_000 {
        if condition() { return true }
        await Task.yield()
      }
      return false
    }
  }

  @Test func aDetectedMeetingCountsOnlyWhileTheModeIsOn() async {
    let rig = Rig(mode: .pause)
    rig.model.start()
    await rig.model.refresh()
    rig.provider.set(.active(.app("Zoom")))
    #expect(await rig.eventually { rig.model.meetingActive })
    #expect(rig.model.meetingReason == .app("Zoom"))
    #expect(!rig.model.isPresentingOverride)
    await rig.pipeline.config.update { $0.meeting.mode = .off }
    await rig.model.refresh()
    #expect(!rig.model.meetingActive)
    #expect(rig.model.meetingReason == nil)
    rig.model.stop()
  }

  @Test func theOverrideWinsAndWorksWithTheModeOff() async {
    let rig = Rig(mode: .off)
    rig.model.start()
    rig.provider.set(.active(.app("Zoom")))
    await rig.model.setPresenting(true)
    #expect(rig.model.isPresentingOverride)
    #expect(rig.model.meetingActive)
    #expect(rig.model.meetingReason == .presenting)
    await rig.model.setPresenting(false)
    #expect(!rig.model.isPresentingOverride)
    #expect(!rig.model.meetingActive)
    rig.model.stop()
  }

  @Test func aTimedOverrideEndsOnItsOwn() async {
    let rig = Rig(mode: .off)
    rig.model.start()
    await rig.model.setPresenting(true, for: 600)
    let stored = await rig.pipeline.config.load().meeting.presentingUntil
    #expect(stored == rig.pipeline.clock.now().addingTimeInterval(600))
    #expect(rig.model.isPresentingOverride)
    for _ in 0..<3000 { await Task.yield() }
    rig.pipeline.clock.advance(by: .seconds(601))
    #expect(await rig.eventually { !rig.model.isPresentingOverride })
    rig.model.stop()
  }

  @Test func presentingLastsAnHourUnlessTold() async {
    let rig = Rig(mode: .off)
    rig.model.start()
    await rig.model.setPresenting(true)
    let stored = await rig.pipeline.config.load().meeting.presentingUntil
    #expect(stored == rig.pipeline.clock.now().addingTimeInterval(3600))
    #expect(rig.model.presentingUntil == stored)
    rig.model.stop()
  }

  @Test func aFailedWriteSurfacesAndTheNextOneClearsIt() async {
    let pipeline = PipelineFixture()
    let source = ManualPipelineSource()
    let model = AppModel(
      source: source, meeting: ManualMeetingState(), config: UnwritableConfigStore(),
      permissions: InMemoryNotificationPermission(.allowed), clock: pipeline.clock,
      configChanges: { AsyncStream { $0.finish() } })
    await model.setPresenting(true)
    #expect(model.presentingError != nil)
    #expect(!model.isPresentingOverride)
  }

  @Test func theReasonFollowsTheSharedEffectiveState() async {
    let rig = Rig(mode: .pause)
    rig.model.start()
    await rig.model.refresh()
    rig.provider.set(.active(.slackHuddle))
    #expect(await rig.eventually { rig.model.meetingReason == .slackHuddle })
    await rig.model.setPresenting(true)
    #expect(rig.model.meetingReason == .presenting)
    rig.model.stop()
  }

  @Test func withoutADetectionOnlyTheOverrideCounts() async {
    let rig = ModelRig()
    rig.model.start()
    await rig.model.setPresenting(true)
    #expect(rig.model.meetingReason == .presenting)
    await rig.model.setPresenting(false)
    #expect(rig.model.meetingReason == nil)
    rig.model.stop()
  }

  @Test func presentingHoldsDeliveryAndEndingItShowsASummary() async throws {
    let rig = ModelRig()
    rig.model.start()
    let fixture = rig.pipeline
    await fixture.delivery.start()
    await rig.model.setPresenting(true)
    let message = fixture.message("m1")
    _ = try await fixture.history.append(message)
    await fixture.delivery.deliver(message)
    for _ in 0..<3000 { await Task.yield() }
    #expect(await fixture.poster.attempts == 0)
    await rig.model.setPresenting(false)
    var summaries = 0
    for _ in 0..<200_000 where summaries == 0 {
      summaries = await fixture.poster.summaries.count
      await Task.yield()
    }
    #expect(await fixture.poster.summaries.first?.cause == .meeting)
    rig.model.stop()
    await fixture.delivery.shutdown()
  }
}

@Suite struct DisplaySharingLinkTests {
  @Test func theHintOpensTheNotificationsPane() {
    #expect(
      NotificationSettingsLink.displaySharingPane?.absoluteString
        == "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    #expect(
      NotificationSettingsLink.appPane?.absoluteString.hasPrefix(
        NotificationSettingsLink.displaySharingPane?.absoluteString ?? "?") == true)
  }
}
