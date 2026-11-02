import Foundation
import NtfyCore

/// `MessageStream` over a long-lived HTTP request to the server's `/json` endpoint.
public struct URLSessionMessageStream: MessageStream {
  private let base: URL
  private let token: String?
  private let session: URLSession

  public init(base: URL, token: String?, session: URLSession = .shared) {
    self.base = base
    self.token = token
    self.session = session
  }

  public func messages(
    topics: [String], since: String?
  ) -> AsyncThrowingStream<NtfyMessage, any Error> {
    guard let url = StreamEndpoint.url(base: base, topics: topics, since: since) else {
      return AsyncThrowingStream(NtfyMessage.self, bufferingPolicy: .unbounded) {
        $0.finish(throwing: NtfyError.invalidResponse("no topics or malformed server URL"))
      }
    }
    var request = URLRequest(url: url)
    request.timeoutInterval = .infinity
    if let token {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }
    let session = session
    return AsyncThrowingStream(NtfyMessage.self, bufferingPolicy: .unbounded) { continuation in
      let task = Task { [request] in
        do {
          let (bytes, response) = try await session.bytes(for: request)
          if let http = response as? HTTPURLResponse, [401, 403].contains(http.statusCode) {
            throw NtfyError.unauthorized
          }
          for try await line in bytes.lines {
            if let message = try EventDecoder.decode(line: Data(line.utf8)) {
              continuation.yield(message)
            }
          }
          continuation.finish()
        } catch let error as NtfyError {
          continuation.finish(throwing: error)
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: NtfyError.serverUnreachable)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }
}
