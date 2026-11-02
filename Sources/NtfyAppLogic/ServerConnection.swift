import Foundation
import NtfyCore

/// Where a connection test stands, for the Server section and the onboarding step.
public enum ServerTestState: Sendable, Hashable {
  case idle
  case testing
  /// The test ended. `.ok` means the URL and token are saved.
  case finished(ServerTestResult)

  public var isSaved: Bool {
    if case .finished(.ok) = self { return true }
    return false
  }

  public var isTesting: Bool { self == .testing }
}

extension ServerTestResult {
  /// What happened and what to do about it, in one or two sentences.
  public var explanation: String {
    switch self {
    case .ok(let topics):
      switch topics.count {
      case 0: "Connected and saved. The account has no subscribed topics yet."
      case 1: "Connected and saved. Found 1 topic: \(topics[0])."
      default:
        "Connected and saved. Found \(topics.count) topics: \(topics.joined(separator: ", "))."
      }
    case .unauthorized:
      "The server rejected the access token. "
        + "Create a new one in the ntfy web app under Account, Access Tokens."
    case .unreachable:
      "Could not reach the server. Check the address, your network or VPN, and try again."
    case .insecure:
      "The token would travel over plain http. Use an https address, or turn on "
        + "\u{201C}Allow the token over plain http\u{201D} in Settings for a server you trust."
    case .redirected:
      "The server redirected the request. The token is never sent to another address, "
        + "so enter the final address, usually the https one."
    case .invalid(let reason): reason
    }
  }
}

/// Test, then save: the one place the Settings window and the onboarding turn a typed URL and
/// token into stored ones. The URL goes to the config, the token to the Keychain only, and
/// nothing is stored unless the test passed.
struct ServerConnection {
  let config: any ConfigStore
  let secrets: any SecretStore
  let tester: any ServerTesting

  /// - Parameter tokenText: Empty keeps the token already in the Keychain.
  func testAndSave(urlText: String, tokenText: String) async -> ServerTestResult {
    let url: URL
    do {
      url = try ServerAddress.parse(urlText)
    } catch {
      return .invalid(reason: error.description)
    }
    let typed = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let token = await effectiveToken(typed) else {
      return .invalid(reason: "Enter the access token.")
    }
    let allowInsecure = (try? await config.load().allowInsecure) ?? false
    let result = await tester.test(
      url: url.absoluteString, token: token, allowInsecure: allowInsecure)
    guard case .ok = result else { return result }
    let address = url.absoluteString
    let previous = try? await config.load()
    do throws(NtfyError) {
      try await config.update { stored in
        stored.url = address
        stored.token = nil
      }
    } catch {
      return .invalid(reason: "The connection works, but saving failed: \(error).")
    }
    guard !typed.isEmpty else { return result }
    do throws(NtfyError) {
      try await secrets.setToken(typed)
    } catch {
      // The URL is already stored; put the old address back so it keeps matching the old token.
      // Without a readable previous config there is nothing safe to put back.
      var reason = "The connection works, but saving failed: \(error)."
      if let previous {
        let (oldURL, oldToken) = (previous.url, previous.token)
        do throws(NtfyError) {
          try await config.update { stored in
            stored.url = oldURL
            stored.token = oldToken
          }
        } catch {
          reason += " The previous settings could not be restored."
        }
      }
      return .invalid(reason: reason)
    }
    return result
  }

  private func effectiveToken(_ typed: String) async -> String? {
    if !typed.isEmpty { return typed }
    guard let stored = try? await secrets.token(), !stored.isEmpty else { return nil }
    return stored
  }
}
