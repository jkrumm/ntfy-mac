import Foundation
import NtfyCore

/// `MessageStream` over a long-lived HTTP request to the server's `/json` endpoint.
///
/// Only transport and HTTP-level failures end the stream. A line that cannot be decoded is
/// reported to `diagnostics` and skipped, so one bad line can never wedge a reconnect loop.
public struct URLSessionMessageStream: MessageStream {
  private let base: URL
  private let token: String?
  private let session: URLSession
  private let diagnostics: @Sendable (String) -> Void

  /// - Parameter session: defaults to an ephemeral session (no cookie or cache storage for an
  ///   authorized stream). Redirects are refused per request, so injected sessions are covered too.
  public init(
    base: URL,
    token: String?,
    session: URLSession = URLSession(configuration: .ephemeral),
    diagnostics: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.base = base
    self.token = token
    self.session = session
    self.diagnostics = diagnostics
  }

  public func messages(
    topics: [String], since: String?
  ) -> AsyncThrowingStream<NtfyMessage, any Error> {
    let url: URL
    do {
      url = try StreamEndpoint.url(base: base, topics: topics, since: since)
    } catch {
      return AsyncThrowingStream(NtfyMessage.self, bufferingPolicy: .unbounded) {
        $0.finish(throwing: error)
      }
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = .infinity
    if let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let (session, diagnostics) = (session, diagnostics)
    return AsyncThrowingStream(NtfyMessage.self, bufferingPolicy: .unbounded) { continuation in
      let task = Task { [request] in
        do {
          try await Self.run(request, on: session, diagnostics: diagnostics) {
            continuation.yield($0)
          }
          continuation.finish()
        } catch let error as NtfyError {
          continuation.finish(throwing: error)
        } catch is CancellationError {
          continuation.finish()
        } catch let error as URLError where error.code == .cancelled {
          continuation.finish()
        } catch {
          continuation.finish(throwing: NtfyError.serverUnreachable)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private static func run(
    _ request: URLRequest,
    on session: URLSession,
    diagnostics: @Sendable (String) -> Void,
    yield: (NtfyMessage) -> Void
  ) async throws {
    let (bytes, response) = try await session.bytes(for: request, delegate: RedirectRefuser())
    guard let http = response as? HTTPURLResponse else {
      throw NtfyError.invalidResponse("not an HTTP response")
    }
    try validate(http, requested: request.url)
    for try await line in bytes.lines {
      do {
        if let message = try EventDecoder.decode(line: Data(line.utf8)) {
          yield(message)
        }
      } catch {
        diagnostics("skipped undecodable stream line (\(line.utf8.count) bytes)")
      }
    }
  }

  private static func validate(_ response: HTTPURLResponse, requested: URL?) throws {
    if let requested, let final = response.url, !sameOrigin(requested, final) {
      throw NtfyError.redirected
    }
    switch response.statusCode {
    case 200..<300:
      let type = response.value(forHTTPHeaderField: "Content-Type")?.lowercased()
      if let type, !type.contains("json") {
        throw NtfyError.invalidResponse("expected an NDJSON stream, got \(type)")
      }
    case 300..<400: throw NtfyError.redirected
    case 401, 403: throw NtfyError.unauthorized
    case 429:
      let retry = response.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) }
      throw NtfyError.rateLimited(retryAfter: retry)
    case 500..<600: throw NtfyError.serverUnreachable
    default: throw NtfyError.invalidResponse("HTTP \(response.statusCode)")
    }
  }

  private static func sameOrigin(_ lhs: URL, _ rhs: URL) -> Bool {
    func origin(_ url: URL) -> [String?] {
      let scheme = url.scheme?.lowercased()
      let port = url.port ?? (scheme == "https" ? 443 : 80)
      return [scheme, url.host?.lowercased(), String(port)]
    }
    return origin(lhs) == origin(rhs)
  }
}

/// Redirects are terminal: following one would send the token to whatever host answered.
private final class RedirectRefuser: NSObject, URLSessionTaskDelegate {
  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
  ) async -> URLRequest? {
    nil
  }
}
