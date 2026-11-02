import Foundation
import NtfyCore
import Observation

/// The notification permission as the Settings window and the onboarding show it: the state, the
/// request, the way into System Settings, and a test notification.
///
/// macOS owns the permission. The flow only reads it (`refresh`, also on every activation of the
/// app, because the user changes it elsewhere) and asks while it is not determined.
@MainActor @Observable
public final class NotificationPermissionFlow {
  public enum TestState: Sendable, Hashable {
    case idle
    case sent
    case failed(String)
  }

  public static let scheduledSummaryWarning =
    "Scheduled Summary is on for ntfy-mac: notifications may be delivered late. Turn it off in System Settings."
  public static let timeSensitiveWarning =
    "Time Sensitive notifications are off: urgent messages will not break through Focus."

  /// Nil until the first check.
  public private(set) var permission: NotificationPermission?
  public private(set) var isRequesting = false
  public private(set) var testState = TestState.idle

  @ObservationIgnored private let permissions: any NotificationPermissionProviding
  @ObservationIgnored private let settings: NotificationSettingsLink
  @ObservationIgnored private let quitGuard: any QuitGuarding
  @ObservationIgnored private let source: any PipelineSource
  @ObservationIgnored private let clock: any NtfyCore.Clock

  public init(
    permissions: any NotificationPermissionProviding, opener: any SystemSettingsOpening,
    quitGuard: any QuitGuarding, source: any PipelineSource, clock: any NtfyCore.Clock
  ) {
    self.permissions = permissions
    settings = NotificationSettingsLink(opener: opener)
    self.quitGuard = quitGuard
    self.source = source
    self.clock = clock
  }

  /// Not asked yet: the system prompt can still be shown.
  public var canRequest: Bool { permission?.authorization == .notDetermined }

  /// Only the user can fix it, in System Settings: denied, or banners and alerts off.
  public var needsSystemSettings: Bool {
    guard let problems = permission?.problems else { return false }
    return problems.contains(.denied) || problems.contains(.alertsOff)
  }

  /// Everything wrong with the permission, most severe first; empty once all is well.
  public var problems: [PermissionProblem] { permission?.problems ?? [] }

  public var scheduledSummaryWarning: String? {
    problems.contains(.scheduledSummary) ? Self.scheduledSummaryWarning : nil
  }

  public var timeSensitiveWarning: String? {
    problems.contains(.timeSensitiveOff) ? Self.timeSensitiveWarning : nil
  }

  public func refresh() async {
    permission = await permissions.current()
  }

  /// Shows the system prompt when the state is not determined. The process cannot be quit while
  /// the prompt is open: quitting then leaves the permission denied for good.
  public func requestAuthorization() async {
    guard canRequest, !isRequesting else { return }
    isRequesting = true
    let release = quitGuard.hold(reason: "notification authorization prompt")
    permission = await permissions.requestAuthorization()
    release()
    isRequesting = false
  }

  public func openSystemSettings() async {
    await settings.open()
  }

  /// Posts a message through the app's own delivery path, so what the user sees is what a real
  /// message does.
  public func sendTestNotification() async {
    guard let messages = await source.current()?.messages else {
      testState = .failed("The app is still starting. Try again in a moment.")
      return
    }
    let message = NtfyMessage(
      id: "local-\(UUID().uuidString.lowercased())", topic: IPCRequestHandler.localTopic,
      time: clock.now(), title: "ntfy-mac", body: "Notifications work.")
    do throws(NtfyError) {
      try await messages.post(message, dismissAfter: nil)
      testState = .sent
    } catch {
      testState = .failed("The notification could not be posted: \(error).")
    }
  }
}
