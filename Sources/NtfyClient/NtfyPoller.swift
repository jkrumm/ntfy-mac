import Foundation
import NtfyCore

/// `MessagePoller` over `?poll=1`: reads what the server cached and closes the connection.
public struct NtfyPoller: MessagePoller {
  private let base: URL
  private let token: String?
  private let allowInsecure: Bool
  private let timeout: TimeInterval
  private let session: URLSession
  private let diagnostics: @Sendable (String) -> Void

  /// - Parameter timeout: per-request limit, covering connect and idle time.
  public init(
    base: URL,
    token: String?,
    allowInsecure: Bool = false,
    timeout: TimeInterval = 30,
    session: URLSession = URLSession(configuration: .ephemeral),
    diagnostics: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.base = base
    self.token = token
    self.allowInsecure = allowInsecure
    self.timeout = timeout
    self.session = session
    self.diagnostics = diagnostics
  }

  public func poll(topics: [String], since: String?) async throws(NtfyError) -> [NtfyMessage] {
    let url = try StreamEndpoint.url(
      base: base, topics: topics, since: since, poll: true, token: token,
      allowInsecure: allowInsecure)
    let request = URLRequest.authorized(url, token: token, timeout: timeout)
    do {
      return try await fetch(request)
    } catch {
      throw ServerResponse.error(from: error)
    }
  }

  private func fetch(_ request: URLRequest) async throws -> [NtfyMessage] {
    let (bytes, response) = try await session.bytes(for: request, delegate: RedirectRefuser())
    try ServerResponse.validate(response, requested: request.url)
    if (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Messages-Truncated") == "1" {
      diagnostics("server truncated the replay: older messages were dropped")
    }
    var messages: [NtfyMessage] = []
    for try await line in bytes.lines {
      do {
        if case .message(let message)? = try EventDecoder.decode(line: Data(line.utf8)) {
          messages.append(message)
        }
      } catch {
        diagnostics("skipped undecodable poll line (\(line.utf8.count) bytes)")
      }
    }
    return messages
  }
}
