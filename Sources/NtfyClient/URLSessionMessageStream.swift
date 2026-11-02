import Foundation
import NtfyCore

/// `MessageStream` over a long-lived HTTP request to the server's `/json` endpoint.
///
/// Only transport and HTTP-level failures end the stream. A line that cannot be decoded is
/// reported to `diagnostics` and skipped, so one bad line can never wedge a reconnect loop.
public struct URLSessionMessageStream: MessageStream {
  private let base: URL
  private let token: String?
  private let allowInsecure: Bool
  private let connectTimeout: Duration
  private let session: URLSession
  private let diagnostics: @Sendable (String) -> Void

  /// - Parameters:
  ///   - allowInsecure: lets the token travel over plain http to a non-loopback host.
  ///   - connectTimeout: time allowed until the response headers arrive; the open body has none.
  ///   - session: defaults to an ephemeral session (no cookie or cache storage for an
  ///     authorized stream). Redirects are refused per request, so injected sessions are covered too.
  public init(
    base: URL,
    token: String?,
    allowInsecure: Bool = false,
    connectTimeout: Duration = .seconds(30),
    session: URLSession = URLSession(configuration: .ephemeral),
    diagnostics: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.base = base
    self.token = token
    self.allowInsecure = allowInsecure
    self.connectTimeout = connectTimeout
    self.session = session
    self.diagnostics = diagnostics
  }

  public func events(
    topics: [String], since: String?
  ) -> AsyncThrowingStream<StreamEvent, any Error> {
    let url: URL
    do {
      url = try StreamEndpoint.url(
        base: base, topics: topics, since: since, token: token, allowInsecure: allowInsecure)
    } catch {
      return AsyncThrowingStream(StreamEvent.self, bufferingPolicy: .unbounded) {
        $0.finish(throwing: error)
      }
    }
    let request = URLRequest.authorized(url, token: token, timeout: .infinity)
    let (session, diagnostics, connectTimeout) = (session, diagnostics, connectTimeout)
    return AsyncThrowingStream(StreamEvent.self, bufferingPolicy: .unbounded) { continuation in
      let task = Task {
        do {
          try await Self.run(
            request, on: session, connectTimeout: connectTimeout, diagnostics: diagnostics
          ) { continuation.yield($0) }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch let error as URLError where error.code == .cancelled {
          continuation.finish()
        } catch {
          continuation.finish(throwing: ServerResponse.error(from: error))
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  private static func run(
    _ request: URLRequest,
    on session: URLSession,
    connectTimeout: Duration,
    diagnostics: @Sendable (String) -> Void,
    yield: (StreamEvent) -> Void
  ) async throws {
    let (bytes, response) = try await withTimeout(connectTimeout) {
      let (bytes, response) = try await session.bytes(for: request, delegate: RedirectRefuser())
      return Connection(bytes: bytes, response: response)
    }.pair
    try ServerResponse.validate(response, requested: request.url)
    for try await line in bytes.lines {
      do {
        if let event = try EventDecoder.decode(line: Data(line.utf8)) {
          yield(event)
        }
      } catch {
        diagnostics("skipped undecodable stream line (\(line.utf8.count) bytes)")
      }
    }
  }
}

/// `URLSession.AsyncBytes` and `URLResponse` are not both `Sendable`; the pair crosses the
/// timeout's task boundary exactly once, from the child that produced it.
private struct Connection: @unchecked Sendable {
  let bytes: URLSession.AsyncBytes
  let response: URLResponse
  var pair: (URLSession.AsyncBytes, URLResponse) { (bytes, response) }
}
