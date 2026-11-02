import NtfyCore
import Testing
import UserNotifications

@testable import NtfyPlatform

@Suite struct NotificationPermissionMappingTests {
  @Test(arguments: [
    (UNAuthorizationStatus.notDetermined, NotificationPermission.Authorization.notDetermined),
    (.denied, .denied),
    (.authorized, .authorized),
    (.provisional, .provisional),
  ])
  func authorization(status: UNAuthorizationStatus, expected: NotificationPermission.Authorization)
  {
    #expect(NotificationPermission(.init(authorization: status)).authorization == expected)
  }

  @Test(arguments: [
    (UNAlertStyle.none, NotificationPermission.AlertStyle.none),
    (.banner, .banner),
    (.alert, .alert),
  ])
  func alertStyle(style: UNAlertStyle, expected: NotificationPermission.AlertStyle) {
    let snapshot = NotificationSettingsSnapshot(authorization: .authorized, alertStyle: style)
    #expect(NotificationPermission(snapshot).alertStyle == expected)
  }

  @Test(arguments: [
    (UNNotificationSetting.enabled, NotificationPermission.Setting.enabled),
    (.disabled, .disabled),
    (.notSupported, .notSupported),
  ])
  func everySettingMapsEachField(
    setting: UNNotificationSetting, expected: NotificationPermission.Setting
  ) {
    let snapshot = NotificationSettingsSnapshot(
      authorization: .authorized, sound: setting, badge: setting, notificationCenter: setting,
      lockScreen: setting, timeSensitive: setting, scheduledDelivery: setting)
    let permission = NotificationPermission(snapshot)
    #expect(permission.sound == expected)
    #expect(permission.badge == expected)
    #expect(permission.notificationCenter == expected)
    #expect(permission.lockScreen == expected)
    #expect(permission.timeSensitive == expected)
    #expect(permission.scheduledSummary == expected)
  }

  @Test func scheduledDeliveryBecomesScheduledSummaryProblem() {
    let snapshot = NotificationSettingsSnapshot(
      authorization: .authorized, scheduledDelivery: .enabled)
    #expect(NotificationPermission(snapshot).problems == [.scheduledSummary])
  }

  @Test func providerReadsTheSettingsAfterRequesting() async {
    let center = FakeNotificationCenter()
    let provider = UserNotificationPermissionProvider(center: center)
    #expect(await provider.requestAuthorization() == .allowed)
    #expect(await center.authorizationRequests == 1)
    #expect(await provider.current() == .allowed)
    #expect(await center.authorizationRequests == 1)
  }
}
