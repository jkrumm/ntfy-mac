import Foundation
import NtfyCore

private struct Account: Decodable {
  let subscriptions: [AccountSubscription]?
}

private struct AccountSubscription: Decodable {
  let topic: String
  let baseURL: String?

  private enum CodingKeys: String, CodingKey {
    case topic
    case baseURL = "base_url"
  }
}

/// `TopicSource` backed by `GET /v1/account`.
public struct NtfyAccountClient: TopicSource {
  private let base: URL
  private let token: String
  private let allowInsecure: Bool
  private let timeout: TimeInterval
  private let session: URLSession

  public init(
    base: URL,
    token: String,
    allowInsecure: Bool = false,
    timeout: TimeInterval = 30,
    session: URLSession = URLSession(configuration: .ephemeral)
  ) {
    self.base = base
    self.token = token
    self.allowInsecure = allowInsecure
    self.timeout = timeout
    self.session = session
  }

  /// Topics of this server in server order, without duplicates. An account can hold subscriptions
  /// to other servers; those are skipped (matched on scheme, host and port). Entries without a
  /// `base_url` are kept.
  public func subscribedTopics() async throws(NtfyError) -> [String] {
    let url = try ServerEndpoint.url(
      base: base, path: "v1/account", token: token, allowInsecure: allowInsecure)
    let request = URLRequest.authorized(url, token: token, timeout: timeout)
    let data: Data
    do {
      let (body, response) = try await session.data(for: request, delegate: RedirectRefuser())
      try ServerResponse.validate(response, requested: url)
      data = body
    } catch {
      throw ServerResponse.error(from: error)
    }
    guard let account = try? JSONDecoder().decode(Account.self, from: data) else {
      throw .invalidResponse("undecodable account response")
    }
    var seen: Set<String> = []
    return (account.subscriptions ?? []).filter(isOurs).map(\.topic).filter {
      seen.insert($0).inserted
    }
  }

  private func isOurs(_ subscription: AccountSubscription) -> Bool {
    guard let raw = subscription.baseURL else { return true }
    guard let url = URL(string: raw) else { return false }
    return Self.origin(url) == Self.origin(base)
  }

  private static func origin(_ url: URL) -> [String?] {
    let scheme = url.scheme?.lowercased()
    return [scheme, url.host()?.lowercased(), String(url.port ?? (scheme == "https" ? 443 : 80))]
  }
}
