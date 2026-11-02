import Foundation
import NtfyCore
import Observation

/// The welcome window: three steps, one window. Server (test, then save), notifications (ask,
/// explain what is wrong, send a test), and the login item (off unless the user opts in).
///
/// Closing the window dismisses the onboarding for good; that lives in the app's
/// `OnboardingState`, so the model does not know about it.
@MainActor @Observable
public final class OnboardingModel {
  public enum Step: Int, Sendable, CaseIterable {
    case server, notifications, login

    public var title: String {
      switch self {
      case .server: "Server"
      case .notifications: "Notifications"
      case .login: "Launch at login"
      }
    }
  }

  public private(set) var step = Step.server
  public private(set) var serverTest = ServerTestState.idle
  /// Why the login item could not be changed.
  public private(set) var loginError: String?

  public var urlText = ""
  /// Typed only; the model never fills it from the Keychain.
  public var tokenText = ""
  /// Opt-in. Applied by `finish()`.
  public var launchAtLogin = false

  public let permission: NotificationPermissionFlow

  @ObservationIgnored private let connection: ServerConnection
  @ObservationIgnored private let loginItems: any LoginItemControlling

  public init(
    config: any ConfigStore, secrets: any SecretStore, tester: any ServerTesting,
    loginItem: any LoginItemControlling, permission: NotificationPermissionFlow
  ) {
    connection = ServerConnection(config: config, secrets: secrets, tester: tester)
    loginItems = loginItem
    self.permission = permission
  }

  /// Back to a clean first step, for the window opening again ("Set up again").
  public func reset() {
    step = .server
    serverTest = .idle
    loginError = nil
    urlText = ""
    tokenText = ""
    launchAtLogin = loginItems.state().isEnabled
  }

  // MARK: Server

  /// Whether the server step can be tested: both fields hold something.
  public var canTest: Bool {
    !urlText.trimmingCharacters(in: .whitespaces).isEmpty
      && !tokenText.trimmingCharacters(in: .whitespaces).isEmpty && !serverTest.isTesting
  }

  /// Tests the address and token; saves them when the server accepts them.
  public func testConnection() async {
    guard canTest else { return }
    serverTest = .testing
    let result = await connection.testAndSave(urlText: urlText, tokenText: tokenText)
    serverTest = .finished(result)
    if serverTest.isSaved { tokenText = "" }
  }

  // MARK: Steps

  public var isFirstStep: Bool { step == Step.allCases.first }
  public var isLastStep: Bool { step == Step.allCases.last }

  /// The server step moves on once the connection is saved; "Skip" is `next()` without it.
  public var canContinue: Bool { step != .server || serverTest.isSaved }

  public func next() {
    guard let following = Step(rawValue: step.rawValue + 1) else { return }
    step = following
  }

  public func back() {
    guard let previous = Step(rawValue: step.rawValue - 1) else { return }
    step = previous
  }

  /// Applies the login-item choice. `false` when macOS refused it (see `loginError`); the window
  /// should stay open then.
  public func finish() async -> Bool {
    loginError = nil
    let current = loginItems.state()
    let matches =
      launchAtLogin ? current == .enabled : [.notRegistered, .notFound].contains(current)
    guard !matches else { return true }
    do throws(NtfyError) {
      _ = try loginItems.setEnabled(launchAtLogin)
      return true
    } catch {
      loginError = "The login item could not be turned \(launchAtLogin ? "on" : "off"): \(error)"
      return false
    }
  }

  /// Re-reads the notification permission; call it when the app becomes active again.
  public func refreshPermission() async {
    await permission.refresh()
  }
}
