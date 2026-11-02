import ArgumentParser
import Foundation
import NtfyCore
import NtfyIPC

/// Reads and changes the app's login item through the app, which alone may do it.
struct LoginItemClient {
  let app: any AppControlling

  /// The state after the optional change.
  func state(
    _ action: LoginItemPayload.Action = .status, launch: Bool
  ) async throws -> LoginItemState {
    let request = Request(
      id: UUID().uuidString, command: .loginItem, loginItem: LoginItemPayload(action: action))
    let response = try await app.send(request, launch: launch)
    guard let raw = try response.requireSuccess()?.loginItem?.state,
      let state = LoginItemState(rawValue: raw)
    else {
      throw CLIFailure.runtime("invalid-response", "The app did not report the login item state.")
    }
    return state
  }
}

enum LoginItemChoice: String, CaseIterable, ExpressibleByArgument {
  case enable = "on"
  case disable = "off"
  case status
}

struct LoginItemCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "login-item", abstract: "Start ntfy-mac at login: on, off or status.",
    discussion: """
      The app owns its login item, so this asks the app (started if needed). States: enabled,
      requiresApproval (approve it in System Settings > General > Login Items), notRegistered,
      notFound.
      """)

  @Argument(help: "on, off or status.") var action: LoginItemChoice
  @OptionGroup var output: OutputOptions

  private struct Report: Encodable {
    let state: String
    let enabled: Bool
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let change: LoginItemPayload.Action =
      switch action {
      case .enable: .enable
      case .disable: .disable
      case .status: .status
      }
    let state = try await LoginItemClient(app: environment.app).state(change, launch: true)
    out.result(Report(state: state.rawValue, enabled: state.isEnabled), text: text(state))
  }

  private func text(_ state: LoginItemState) -> String {
    switch state {
    case .enabled: "ntfy-mac starts at login."
    case .notRegistered: "ntfy-mac does not start at login. Enable it with: ntfy-mac login-item on"
    case .requiresApproval:
      "Approve ntfy-mac in System Settings > General > Login Items to start it at login."
    case .notFound: "The app cannot be registered as a login item from here; install it first."
    }
  }
}
