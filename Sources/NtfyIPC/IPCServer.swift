import Darwin
import Foundation
import Synchronization

/// Serves the app side of the socket: one request and one response per connection, framed as
/// NDJSON, answered by the injected handler.
///
/// - The directory is 0700, the socket 0600, and a peer running as another user is dropped.
/// - An exclusive `flock` on `app.sock.lock`, held until `stop`, serializes the stale-socket check
///   and the bind: a second server (same process or not) gets `alreadyRunning` without touching
///   the first one's socket. Only a socket this server bound itself is removed again.
/// - A socket left by a crashed run is detected (`ECONNREFUSED`) and rebound; a live one makes
///   `start` throw `alreadyRunning`.
/// - A frame over `Limits.maxFrameBytes` or a peer too slow to send one is cut off, and a handler
///   that does not answer within `Limits.handlerTimeout` gets an `internal` error response; the
///   slot is free again even if the handler never returns.
public final class IPCServer: Sendable {
  public typealias Handler = @Sendable (Request) async -> Response

  public struct Limits: Sendable {
    public var maxFrameBytes = 64 * 1024
    public var readTimeout: Duration = .seconds(5)
    public var writeTimeout: Duration = .seconds(5)
    public var maxConnections = 32
    public var handlerTimeout: Duration = .seconds(30)

    public init() {}
  }

  private struct State {
    var listener: Int32?
    var lock: Int32?
    var bound: SocketIdentity?
    var acceptTask: Task<Void, Never>?
    var connections: [Int: Task<Void, Never>] = [:]
    var nextID = 0
    var stopped = false
  }

  private let path: URL
  private let limits: Limits
  private let handler: Handler
  private let log: @Sendable (String) -> Void
  private let state = Mutex(State())

  public init(
    path: URL, limits: Limits = Limits(), log: @escaping @Sendable (String) -> Void = { _ in },
    handler: @escaping Handler
  ) {
    self.path = path
    self.limits = limits
    self.log = log
    self.handler = handler
  }

  /// Binds the socket and starts accepting. Throws when it cannot, or when another server
  /// owns the socket. Call at most once.
  public func start() throws(IPCError) {
    try SocketPath.validate(path)
    try SocketPath.prepareDirectory(of: path)
    let lock = try POSIXSocket.acquireLock(at: path.path + ".lock")
    let listener: Int32
    let identity: SocketIdentity
    do throws(IPCError) {
      try Self.clearStaleSocket(at: path.path)
      (listener, identity) = try bindListener()
    } catch {
      close(lock)
      throw error
    }
    let task = Task { await self.acceptLoop(listener) }
    state.withLock {
      $0.listener = listener
      $0.lock = lock
      $0.bound = identity
      $0.acceptTask = task
    }
  }

  /// Binds and listens. A socket file is removed again on failure only once this call created it.
  private func bindListener() throws(IPCError) -> (Int32, SocketIdentity) {
    let listener = try POSIXSocket.makeSocket()
    do throws(IPCError) {
      try POSIXSocket.bind(listener, to: path.path)
    } catch {
      close(listener)
      throw error
    }
    guard let identity = SocketIdentity(path: path.path) else {
      close(listener)
      throw .system("bind", ENOENT)
    }
    guard chmod(path.path, 0o600) == 0, listen(listener, SOMAXCONN) == 0 else {
      let code = errno
      close(listener)
      removeIfOurs(identity)
      throw .system("listen", code)
    }
    return (listener, identity)
  }

  private func removeIfOurs(_ identity: SocketIdentity) {
    guard SocketIdentity(path: path.path) == identity else { return }
    unlink(path.path)
  }

  /// Stops accepting, cancels open connections, waits for them and removes the socket file.
  public func stop() async {
    let (listener, lock, identity, accepting, connections) = state.withLock { state in
      state.stopped = true
      defer {
        state.listener = nil
        state.lock = nil
        state.bound = nil
        state.acceptTask = nil
        state.connections = [:]
      }
      return (
        state.listener, state.lock, state.bound, state.acceptTask,
        Array(state.connections.values)
      )
    }
    accepting?.cancel()
    for task in connections { task.cancel() }
    await accepting?.value
    for task in connections { await task.value }
    if let listener { close(listener) }
    if let identity { removeIfOurs(identity) }
    if let lock { close(lock) }  // closing the descriptor releases the lock
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
    var backoff = AcceptBackoff()
    while !Task.isCancelled {
      guard await POSIXSocket.waitReadable(listener) else { continue }
      let descriptor = accept(listener, nil, nil)
      guard descriptor >= 0 else {
        let code = errno
        switch AcceptFailure.classify(code) {
        case .retry: continue
        case .stop: return
        case .backOff:
          if backoff.isFirstFailure { log("accept failed: errno \(code); backing off") }
          try? await Task.sleep(for: backoff.next())
          continue
        }
      }
      backoff.reset()
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
      response = await answer(try NDJSON.decode(Request.self, from: line))
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

  /// The handler's answer, or an `internal` error once `handlerTimeout` passed. The handler runs
  /// unstructured, so one that ignores cancellation cannot hold this connection (or `stop`).
  private func answer(_ request: Request) async -> Response {
    let (answers, continuation) = AsyncStream<Response>.makeStream(
      bufferingPolicy: .bufferingOldest(1))
    let handler = handler
    let timeout = limits.handlerTimeout
    let work = Task {
      continuation.yield(await handler(request))
      continuation.finish()
    }
    let timer = Task {
      guard (try? await Task.sleep(for: timeout)) != nil else { return }
      continuation.yield(
        .failure(id: request.id, code: .internalError, message: "the request timed out"))
      continuation.finish()
    }
    defer {
      work.cancel()
      timer.cancel()
    }
    for await response in answers { return response }
    return .failure(id: request.id, code: .internalError, message: "the app is shutting down")
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
