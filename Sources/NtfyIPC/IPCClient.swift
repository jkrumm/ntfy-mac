import Darwin
import Foundation

/// Sends one request to the app over its socket and returns the response.
public struct IPCClient: Sendable {
  private let path: URL
  private let connectTimeout: Duration
  private let responseTimeout: Duration
  private let maxResponseBytes: Int

  public init(
    path: URL, connectTimeout: Duration = .seconds(1), responseTimeout: Duration = .seconds(10),
    maxResponseBytes: Int = 1 << 20
  ) {
    self.path = path
    self.connectTimeout = connectTimeout
    self.responseTimeout = responseTimeout
    self.maxResponseBytes = maxResponseBytes
  }

  /// Throws `appNotRunning` when nothing listens on the socket, `timedOut` when the app does
  /// not answer in time.
  public func send(_ request: Request) async throws(IPCError) -> Response {
    try SocketPath.validate(path)
    let frame = try NDJSON.encode(request)
    let descriptor = try await connect()
    defer { close(descriptor) }
    try await POSIXSocket.writeAll(descriptor, frame, timeout: connectTimeout)
    let line = try await POSIXSocket.readLine(
      descriptor, limit: maxResponseBytes, timeout: responseTimeout)
    return try NDJSON.decode(Response.self, from: line)
  }

  /// A full backlog (`EAGAIN`) is retried until the connect timeout.
  private func connect() async throws(IPCError) -> Int32 {
    let deadline = ContinuousClock.now.advanced(by: connectTimeout)
    while true {
      let descriptor = try POSIXSocket.makeSocket()
      let result: Int32
      do throws(IPCError) {
        result = try POSIXSocket.connect(descriptor, to: path.path)
      } catch {
        close(descriptor)
        throw error
      }
      if result == 0 { return descriptor }
      close(descriptor)
      switch result {
      case ENOENT, ECONNREFUSED:
        throw .appNotRunning
      case EAGAIN, EINPROGRESS:
        guard ContinuousClock.now < deadline else { throw .timedOut }
        try? await Task.sleep(for: .milliseconds(10))
        if Task.isCancelled { throw .cancelled }
      default:
        throw .system("connect", result)
      }
    }
  }
}
