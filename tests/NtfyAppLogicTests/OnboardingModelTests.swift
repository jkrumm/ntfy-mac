import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

@MainActor
private struct OnboardingRig {
  let config = InMemoryConfigStore()
  let secrets = InMemorySecretStore()
  let tester: ScriptedServerTester
  let loginItem: InMemoryLoginItem
  let permissions: InMemoryNotificationPermission
  let opener: RecordingOpener
  let quitGuard = RecordingQuitGuard()
  let pipeline = PipelineFixture()
  let source = ManualPipelineSource()
  let model: OnboardingModel

  init(
    test: ServerTestResult = .ok(topics: ["alerts"]),
    permission: NotificationPermission = NotificationPermission(authorization: .notDetermined),
    afterRequest: NotificationPermission = .allowed,
    loginItem: InMemoryLoginItem = InMemoryLoginItem(),
    opener: RecordingOpener = RecordingOpener()
  ) {
    tester = ScriptedServerTester(test)
    self.loginItem = loginItem
    permissions = InMemoryNotificationPermission(permission, afterRequest: afterRequest)
    self.opener = opener
    source.set(pipeline.handles)
    let flow = NotificationPermissionFlow(
      permissions: permissions, opener: opener, quitGuard: quitGuard, source: source,
      clock: pipeline.clock)
    model = OnboardingModel(
      config: config, secrets: secrets, tester: tester, loginItem: loginItem, permission: flow)
  }
}

@MainActor @Suite struct OnboardingModelTests {
  @Test func theServerStepSavesOnSuccessAndOnlyThenContinues() async {
    let rig = OnboardingRig(test: .ok(topics: ["alerts", "ops"]))
    #expect(!rig.model.canTest)
    rig.model.urlText = "ntfy.example.com"
    rig.model.tokenText = "tk_x"
    #expect(rig.model.canTest && !rig.model.canContinue)
    await rig.model.testConnection()
    #expect(rig.model.serverTest == .finished(.ok(topics: ["alerts", "ops"])))
    #expect(rig.model.serverTest.isSaved && rig.model.canContinue)
    #expect(await rig.config.load().url == "https://ntfy.example.com")
    #expect(await rig.config.load().token == nil)
    #expect(await rig.secrets.token() == "tk_x")
    #expect(rig.model.tokenText.isEmpty)
  }

  @Test(arguments: [
    ServerTestResult.unauthorized, .unreachable, .insecure, .redirected, .invalid(reason: "no"),
  ])
  func aFailedTestSavesNothingAndStaysOnTheStep(result: ServerTestResult) async {
    let rig = OnboardingRig(test: result)
    rig.model.urlText = "https://ntfy.example.com"
    rig.model.tokenText = "tk_x"
    await rig.model.testConnection()
    #expect(rig.model.serverTest == .finished(result))
    #expect(!rig.model.canContinue)
    #expect(await rig.config.load().url == nil)
    #expect(await rig.secrets.token() == nil)
    rig.model.next()
    #expect(rig.model.step == .notifications, "Skip is next() without a saved server")
  }

  @Test func stepsMoveForwardAndBackWithinTheirBounds() {
    let model = OnboardingRig().model
    #expect(model.step == .server && model.isFirstStep)
    model.back()
    #expect(model.step == .server)
    model.next()
    model.next()
    #expect(model.step == .login && model.isLastStep)
    model.next()
    #expect(model.step == .login)
    model.back()
    #expect(model.step == .notifications)
  }

  @Test func theLoginItemStaysOffUnlessChosen() async {
    let off = OnboardingRig()
    #expect(!off.model.launchAtLogin)
    #expect(await off.model.finish())
    #expect(off.loginItem.state() == .notRegistered)
    let chosen = OnboardingRig()
    chosen.model.launchAtLogin = true
    #expect(await chosen.model.finish())
    #expect(chosen.loginItem.state() == .enabled)
  }

  // MARK: Notifications

  @Test func theAuthorizationPromptHoldsTheQuitGuardAndUpdatesTheState() async {
    let rig = OnboardingRig()
    await rig.model.refreshPermission()
    #expect(rig.model.permission.canRequest)
    await rig.model.permission.requestAuthorization()
    #expect(rig.quitGuard.holds == 1 && rig.quitGuard.releases == 1)
    #expect(rig.model.permission.permission == .allowed)
    #expect(await rig.permissions.requests == 1)
    await rig.model.permission.requestAuthorization()
    #expect(await rig.permissions.requests == 1, "already determined, no second prompt")
  }

  @Test func aDeniedPermissionOffersSystemSettingsAndRechecks() async throws {
    let rig = OnboardingRig(permission: NotificationPermission(authorization: .denied))
    await rig.model.refreshPermission()
    let flow = rig.model.permission
    #expect(flow.needsSystemSettings && !flow.canRequest)
    await flow.openSystemSettings()
    #expect(rig.opener.opened == [try #require(NotificationSettingsLink.appPane)])
    await rig.permissions.set(.allowed)
    await rig.model.refreshPermission()
    #expect(!flow.needsSystemSettings && flow.problems.isEmpty)
  }

  @Test func theDeepLinkFallsBackToThePaneWhenTheAppIdIsRefused() async {
    let opener = RecordingOpener { !$0.absoluteString.contains("id=") }
    let rig = OnboardingRig(
      permission: NotificationPermission(authorization: .denied), opener: opener)
    await rig.model.permission.openSystemSettings()
    #expect(
      opener.opened.map(\.absoluteString) == [
        "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=com.jkrumm.ntfy-mac",
        "x-apple.systempreferences:com.apple.Notifications-Settings.extension",
      ])
  }

  @Test func alertsOffNeedsSystemSettingsToo() async {
    let rig = OnboardingRig(
      permission: NotificationPermission(authorization: .authorized, alertStyle: .none))
    await rig.model.refreshPermission()
    #expect(rig.model.permission.needsSystemSettings)
  }

  @Test func scheduledSummaryAndTimeSensitiveWarnAboutLateAndQuietNotifications() async {
    let rig = OnboardingRig(
      permission: NotificationPermission(
        authorization: .authorized, timeSensitive: .disabled, scheduledSummary: .enabled))
    await rig.model.refreshPermission()
    let flow = rig.model.permission
    #expect(flow.scheduledSummaryWarning?.contains("delivered late") == true)
    #expect(flow.timeSensitiveWarning?.contains("Focus") == true)
    await rig.permissions.set(.allowed)
    await rig.model.refreshPermission()
    #expect(flow.scheduledSummaryWarning == nil && flow.timeSensitiveWarning == nil)
  }

  @Test func aTestNotificationGoesThroughTheDeliveryPath() async {
    let rig = OnboardingRig(permission: .allowed)
    await rig.model.permission.sendTestNotification()
    #expect(rig.model.permission.testState == .sent)
    var posted = 0
    for _ in 0..<2000 where posted == 0 {
      posted = await rig.pipeline.poster.posted.count
      await Task.yield()
    }
    #expect(posted == 1)
  }

  @Test func aTestNotificationWithoutAPipelineSaysSo() async {
    let rig = OnboardingRig(permission: .allowed)
    rig.source.set(nil)
    await rig.model.permission.sendTestNotification()
    guard case .failed(let reason) = rig.model.permission.testState else {
      Issue.record("expected a failure")
      return
    }
    #expect(reason.contains("starting"))
  }
}
