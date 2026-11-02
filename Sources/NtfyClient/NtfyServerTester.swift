import Foundation
import NtfyCore

/// `ServerTesting` over `GET /v1/account`, with the same URL, token and redirect rules as the
/// stream.
public struct NtfyServerTester: ServerTesting {
  private let timeout: TimeInterval
  private let session: URLSession

  public init(
    timeout: TimeInterval = 15, session: URLSession = URLSession(configuration: .ephemeral)
  ) {
    self.timeout = timeout
    self.session = session
  }

  public func test(url: String, token: String, allowInsecure: Bool) async -> ServerTestResult {
    let base: URL
    do {
      base = try ServerAddress.parse(url)
    } catch {
      return .invalid(reason: error.description)
    }
    let client = NtfyAccountClient(
      base: base, token: token, allowInsecure: allowInsecure, timeout: timeout, session: session)
    do {
      return .ok(topics: try await client.subscribedTopics())
    } catch {
      return Self.result(for: error)
    }
  }

  static func result(for error: NtfyError) -> ServerTestResult {
    switch error {
    case .unauthorized: .unauthorized
    case .serverUnreachable: .unreachable
    case .insecureServer: .insecure
    case .redirected: .redirected
    case .rateLimited: .invalid(reason: "The server is limiting requests; try again in a minute.")
    case .invalidResponse(let detail):
      .invalid(reason: "This does not look like an ntfy server (\(detail)).")
    case .invalidTopic, .appUnavailable, .permissionDenied, .storage:
      .invalid(reason: "The test failed: \(error).")
    }
  }
}
