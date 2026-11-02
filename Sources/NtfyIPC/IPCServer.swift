import Darwin
import Foundation
import Synchronization

/// Serves the app side of the socket: one request and one response per connection, framed as
/// NDJSON, answered by the injected handler.
///
/// - The directory is 0700, the socket 0600, and a peer running as another user is dropped.
/// - A socket left by a crashed run is detected (`ECONNREFUSED`) and rebound; a live one makes
///   `start` throw `alreadyRunning`.
/// - A frame over `Limits.maxFrameBytes` or a peer too slow to send one is cut off.
public final class IPCServer: Sendable {
  public typealias Handler = @Sendable (Request) async -> Response

  public struct Limits: Sendable {
    public var maxFrameBytes = 64 * 1024
    public var readTimeout: Duration = .seconds(5)
    public var writeTimeout: Duration = .seconds(5)
    public var maxConnections = 32

    public init() {}
  }

  private struct State {
    var listener: Int32?
    var acceptTask: Task<Void, Never>?
    var connections: [Int: Task<Void, Never>] = [:]
    var nextID = 0
    var stopped = false
  }

  private let path: URL
  private let limits: Limits
  private let handler: Handler
  private let state = Mutex(State())

  public init(path: URL, limits: Limits = Limits(), handler: @escaping Handler) {
    self.path = path
    self.limits = limits
    self.handler = handler
  }

  /// Binds the socket and starts accepting. Throws when it cannot, or when another server
  /// owns the socket. Call at most once.
  public func start() throws(IPCError) {
    try SocketPath.validate(path)
    try SocketPath.prepareDirectory(of: path)
    try Self.clearStaleSocket(at: path.path)
    let listener = try POSIXSocket.makeSocket()
    do throws(IPCError) {
      try POSIXSocket.bind(listener, to: path.path)
      guard chmod(path.path, 0o600) == 0, listen(listener, SOMAXCONN) == 0 else {
        throw IPCError.system("listen", errno)
      }
    } catch {
      close(listener)
      unlink(path.path)
      throw error
    }
    let task = Task { await self.acceptLoop(listener) }
    state.withLock {
      $0.listener = listener
      $0.acceptTask = task
    }
  }

  /// Stops accepting, cancels open connections, waits for them and removes the socket file.
  public func stop() async {
    let (listener, accepting, connections) = state.withLock { state in
      state.stopped = true
      defer {
        state.listener = nil
        state.acceptTask = nil
        state.connections = [:]
      }
      return (state.listener, state.acceptTask, Array(state.connections.values))
    }
    accepting?.cancel()
    for task in connections { task.cancel() }
    await accepting?.value
    for task in connections { await task.value }
    guard let listener else { return }
    close(listener)
    unlink(path.path)
  }

  // MARK: Accepting

  private static func clearStaleSocket(at path: String) throws(IPCError) {
    var info = stat()
    guard lstat(path, &info) == 0 else { return }
    guard info.st_mode & S_IFMT == S_IFSOCK else { throw .system("not a socket", ENOTSOCK) }
    let probe = try POSIXSocket.makeSocket()
    defer { close(probe) }
    switch try POSIXSocket.connect(probe, to: path) {
    case 0, EAGAIN, EINPROGRESS: throw .alreadyRunning
    case ECONNREFUSED, ENOENT: unlink(path)
    case let code: throw .system("connect", code)
    }
  }

  private func acceptLoop(_ listener: Int32) async {
    while !Task.isCancelled {
      guard await POSIXSocket.waitReadable(listener) else { continue }
      let descriptor = accept(listener, nil, nil)
      guard descriptor >= 0 else { continue }
      guard (try? POSIXSocket.configure(descriptor)) != nil, admit(descriptor) else {
        close(descriptor)
        continue
      }
    }
  }

  /// Registers a task for the connection; false when stopped or full.
  private func admit(_ descriptor: Int32) -> Bool {
    state.withLock { state in
      guard !state.stopped, state.connections.count < limits.maxConnections else { return false }
      let id = state.nextID
      state.nextID += 1
      state.connections[id] = Task {
        await self.serve(descriptor)
        close(descriptor)
        self.state.withLock { _ = $0.connections.removeValue(forKey: id) }
      }
      return true
    }
  }

  // MARK: Serving

  private func serve(_ descriptor: Int32) async {
    guard POSIXSocket.peerIsCurrentUser(descriptor) else { return }
    let response: Response
    do throws(IPCError) {
      let line = try await POSIXSocket.readLine(
        descriptor, limit: limits.maxFrameBytes, timeout: limits.readTimeout)
      response = await handler(try NDJSON.decode(Request.self, from: line))
    } catch {
      guard let rejection = Self.rejection(for: error) else { return }
      response = rejection
    }
    guard let frame = try? NDJSON.encode(response) else { return }
    do throws(IPCError) {
      try await POSIXSocket.writeAll(descriptor, frame, timeout: limits.writeTimeout)
    } catch {
      return
    }
    shutdown(descriptor, SHUT_WR)
    await POSIXSocket.drain(descriptor, limit: 1 << 20, timeout: .milliseconds(250))
  }

  /// The error response for a request that could not be read; nil when the peer is gone.
  private static func rejection(for error: IPCError) -> Response? {
    switch error {
    case .unsupportedProtocolVersion(let version):
      .failure(
        id: "", code: .unsupportedVersion,
        message: "protocol version \(version) is not supported (expected \(IPC.protocolVersion))")
    case .malformedFrame:
      .failure(id: "", code: .badRequest, message: "request is not a valid frame")
    case .frameTooLarge:
      .failure(id: "", code: .badRequest, message: "request is too large")
    default:
      nil
    }
  }
}
