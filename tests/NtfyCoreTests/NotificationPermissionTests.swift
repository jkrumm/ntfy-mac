import Foundation
import Testing

@testable import NtfyCore

@Suite struct NotificationPermissionTests {
  private static func permission(
    _ authorization: NotificationPermission.Authorization,
    alerts: NotificationPermission.AlertStyle = .banner,
    center: NotificationPermission.Setting = .enabled,
    sound: NotificationPermission.Setting = .enabled,
    timeSensitive: NotificationPermission.Setting = .enabled,
    summary: NotificationPermission.Setting = .disabled
  ) -> NotificationPermission {
    NotificationPermission(
      authorization: authorization, alertStyle: alerts, sound: sound,
      notificationCenter: center, timeSensitive: timeSensitive, scheduledSummary: summary)
  }

  @Test(arguments: [
    (permission(.authorized), true),
    (permission(.provisional), true),
    (permission(.authorized, alerts: .alert), true),
    (permission(.authorized, alerts: .none, center: .enabled), true),
    (permission(.authorized, alerts: .none, center: .disabled), false),
    (permission(.authorized, alerts: .none, center: .notSupported), false),
    (permission(.ephemeral), false),
    (permission(.denied), false),
    (permission(.notDetermined), false),
  ])
  func usability(_ permission: NotificationPermission, _ expected: Bool) {
    #expect(permission.isUsable == expected)
  }

  @Test(arguments: [
    (permission(.authorized), []),
    (permission(.provisional), []),
    (permission(.notDetermined), ["not-determined"]),
    (permission(.denied, alerts: .none, sound: .disabled), ["denied"]),
    (permission(.authorized, alerts: .none), ["alerts-off"]),
    (permission(.authorized, sound: .disabled), ["sound-off"]),
    (permission(.authorized, sound: .notSupported, timeSensitive: .notSupported), []),
    (permission(.authorized, timeSensitive: .disabled), ["time-sensitive-off"]),
    (permission(.authorized, summary: .enabled), ["scheduled-summary"]),
    (permission(.authorized, summary: .notSupported), []),
    (
      permission(
        .authorized, alerts: .none, sound: .disabled, timeSensitive: .disabled, summary: .enabled),
      ["alerts-off", "scheduled-summary", "time-sensitive-off", "sound-off"]
    ),
  ])
  func problemCodes(_ permission: NotificationPermission, _ codes: [String]) {
    #expect(permission.problems.map(\.code) == codes)
  }

  @Test func everyProblemHasAOneLineHint() {
    let worst = Self.permission(
      .authorized, alerts: .none, sound: .disabled, timeSensitive: .disabled, summary: .enabled)
    let all =
      worst.problems + Self.permission(.denied).problems
      + Self.permission(.notDetermined).problems
    #expect(all.count == 6)
    for problem in all {
      #expect(!problem.hint.isEmpty)
      #expect(!problem.hint.contains("\n"))
    }
  }

  @Test func deniedHintPointsToSystemSettings() {
    #expect(
      Self.permission(.denied).problems.first?.hint
        == "Allow notifications for ntfy-mac in System Settings > Notifications")
  }

  @Test func roundTripsThroughCodable() throws {
    let value = Self.permission(.provisional, alerts: .alert, summary: .enabled)
    let data = try JSONEncoder().encode(value)
    #expect(try JSONDecoder().decode(NotificationPermission.self, from: data) == value)
  }
}
