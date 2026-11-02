import Foundation
import NtfyCore
import Synchronization

/// Streams one request's body into a file as URLSession delivers it, in chunks rather than byte
/// by byte. The status and declared size are checked before the first chunk, redirects are
/// refused, and a chunk that would take the total past `limit` fails the download before it is
/// written.
///
/// The delegate callbacks (`total` and `failure`) rely on the session's delegate queue being
/// serial, which is what `URLSession` creates by default; a session built with a concurrent
/// queue would break that. The hand-off between the caller and the delegate queue goes through
/// `state` and is safe from any thread: the completion may arrive before the caller has
/// installed its continuation (a task cancelled before it starts), and whichever of the two
/// comes second resumes the caller, exactly once.
final class ChunkedDownload: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  static let tooLarge = NtfyError.invalidResponse("the attachment is larger than 50 MB")

  private struct State {
    var continuation: CheckedContinuation<Void, any Error>?
    var outcome: Result<Void, any Error>?
  }

  private let handle: FileHandle
  private let limit: Int64
  private let state = Mutex(State())
  // Delegate queue only (serial).
  private var total: Int64 = 0
  private var failure: (any Error)?

  private init(handle: FileHandle, limit: Int64) {
    self.handle = handle
    self.limit = limit
  }

  static func run(
    _ request: URLRequest, on session: URLSession, limit: Int64, into handle: FileHandle
  ) async throws {
    try Task.checkCancellation()
    let download = ChunkedDownload(handle: handle, limit: limit)
    let task = session.dataTask(with: request)
    task.delegate = download
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        download.install(continuation)
        task.resume()
      }
    } onCancel: {
      download.finish(.failure(CancellationError()))
      task.cancel()
    }
  }

  /// Hands the caller's continuation over; resumes it at once if the download already ended.
  private func install(_ continuation: CheckedContinuation<Void, any Error>) {
    let finished = state.withLock { state -> Result<Void, any Error>? in
      if let outcome = state.outcome { return outcome }
      state.continuation = continuation
      return nil
    }
    if let finished { continuation.resume(with: finished) }
  }

  /// Records how the download ended (the first outcome wins) and resumes the caller if it is
  /// already waiting.
  private func finish(_ outcome: Result<Void, any Error>) {
    let waiting = state.withLock { state -> CheckedContinuation<Void, any Error>? in
      guard state.outcome == nil else { return nil }
      state.outcome = outcome
      defer { state.continuation = nil }
      return state.continuation
    }
    waiting?.resume(with: outcome)
  }

  private var isFinished: Bool { state.withLock { $0.outcome != nil } }

  /// Status and declared size, before a byte is stored.
  private static func check(_ response: URLResponse, limit: Int64) throws {
    guard let http = response as? HTTPURLResponse else {
      throw NtfyError.invalidResponse("not an HTTP response")
    }
    switch http.statusCode {
    case 200..<300: break
    case 300..<400: throw NtfyError.redirected
    case 401, 403: throw NtfyError.unauthorized
    case 500..<600: throw NtfyError.serverUnreachable
    default: throw NtfyError.invalidResponse("HTTP \(http.statusCode)")
    }
    if let declared = Int64(http.value(forHTTPHeaderField: "Content-Length") ?? ""),
      declared > limit
    {
      throw tooLarge
    }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask,
    willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
    completionHandler: @escaping @Sendable (URLRequest?) -> Void
  ) {
    completionHandler(nil)
  }

  func urlSession(
    _ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
    completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
  ) {
    do {
      try Self.check(response, limit: limit)
      completionHandler(.allow)
    } catch {
      failure = error
      completionHandler(.cancel)
    }
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    guard failure == nil, !isFinished else { return }
    guard total + Int64(data.count) <= limit else {
      failure = Self.tooLarge
      dataTask.cancel()
      return
    }
    total += Int64(data.count)
    do {
      try handle.write(contentsOf: data)
    } catch {
      failure = error
      dataTask.cancel()
    }
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
  ) {
    if let outcome = failure ?? error {
      finish(.failure(outcome))
    } else {
      finish(.success(()))
    }
  }
}
