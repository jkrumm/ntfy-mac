import Darwin
import Foundation
import Testing

@testable import NtfyIPC

/// A short-lived directory under /tmp: a socket path must fit 103 bytes, which the system temp
/// dir plus a UUID does not. Tests never touch the real application support directory.
private struct SocketDirectory: ~Copyable {
  let url = URL(fileURLWithPath: "/tmp/ntfyipc-\(UUID().uuidString.prefix(8))", isDirectory: true)
  var socket: URL { url.appending(path: "app.sock", directoryHint: .notDirectory) }

  deinit { try? FileManager.default.removeItem(at: url) }
}

private let echo: IPCServer.Handler = { request in
  switch request.command {
  case .ping: .success(id: request.id)
  case .status:
    .success(
      id: request.id,
      result: ResultPayload(status: StatusResult(connection: "connected", appVersion: "t")))
  default: .failure(id: request.id, code: .badRequest, message: "unsupported")
  }
}

private func mode(_ url: URL) throws -> Int {
  (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) ?? -1
}

@Suite struct IPCSocketTests {
  @Test func answersARequestAndLocksDownPermissions() async throws {
    let directory = SocketDirectory()
    let server = IPCServer(path: directory.socket, handler: echo)
    try server.start()
    #expect(try mode(directory.url) == 0o700)
    #expect(try mode(directory.socket) == 0o600)
    let client = IPCClient(path: directory.socket)
    let response = try await client.send(Request(id: "a", command: .status))
    #expect(response.id == "a")
    #expect(response.result?.status?.connection == "connected")
    await server.stop()
    #expect(!FileManager.default.fileExists(atPath: directory.socket.path))
  }

  @Test func handlerErrorsReachTheClient() async throws {
    let directory = SocketDirectory()
    let server = IPCServer(path: directory.socket, handler: echo)
    try server.start()
    let response = try await IPCClient(path: directory.socket).send(
      Request(id: "a", command: .reconnect))
    #expect(response.status == .error)
    #expect(response.code == .badRequest)
    await server.stop()
  }

  @Test func garbageGetsABadRequestResponse() async throws {
    let directory = SocketDirectory()
    let server = IPCServer(path: directory.socket, handler: echo)
    try server.start()
    let line = try await rawExchange(directory.socket, Data("not json\n".utf8))
    let response = try NDJSON.decode(Response.self, from: line)
    #expect(response.code == .badRequest)
    await server.stop()
  }

  @Test func aFutureProtocolVersionIsRefused() async throws {
    let directory = SocketDirectory()
    let server = IPCServer(path: directory.socket, handler: echo)
    try server.start()
    let frame = Data(#"{"command":"ping","id":"1","protocolVersion":9}"#.utf8) + Data("\n".utf8)
    let response = try NDJSON.decode(
      Response.self, from: try await rawExchange(directory.socket, frame))
    #expect(response.code == .unsupportedVersion)
    await server.stop()
  }

  @Test func anOversizedFrameIsRejectedAndTheServerKeepsWorking() async throws {
    let directory = SocketDirectory()
    var limits = IPCServer.Limits()
    limits.maxFrameBytes = 1024
    let server = IPCServer(path: directory.socket, limits: limits, handler: echo)
    try server.start()
    let client = IPCClient(path: directory.socket)
    let huge = Request(
      id: "big", command: .notify, notify: NotifyPayload(body: String(repeating: "x", count: 8192)))
    let rejected = try await client.send(huge)
    #expect(rejected.code == .badRequest)
    let fine = try await client.send(Request(id: "ok", command: .ping))
    #expect(fine.status == .success)
    await server.stop()
  }

  @Test func aSilentPeerIsCutOffByTheReadTimeout() async throws {
    let directory = SocketDirectory()
    var limits = IPCServer.Limits()
    limits.readTimeout = .milliseconds(200)
    let server = IPCServer(path: directory.socket, limits: limits, handler: echo)
    try server.start()
    let descriptor = try POSIXSocket.makeSocket()
    defer { close(descriptor) }
    #expect(try POSIXSocket.connect(descriptor, to: directory.socket.path) == 0)
    await #expect(throws: IPCError.connectionClosed) {
      try await POSIXSocket.readLine(descriptor, limit: 1024, timeout: .seconds(5))
    }
    await server.stop()
  }

  @Test func aStaleSocketIsReplaced() async throws {
    let directory = SocketDirectory()
    try SocketPath.prepareDirectory(of: directory.socket)
    let dead = try POSIXSocket.makeSocket()
    try POSIXSocket.bind(dead, to: directory.socket.path)
    close(dead)  // leaves the file behind with nobody listening, as after kill -9
    #expect(FileManager.default.fileExists(atPath: directory.socket.path))
    let server = IPCServer(path: directory.socket, handler: echo)
    try server.start()
    let response = try await IPCClient(path: directory.socket).send(
      Request(id: "a", command: .ping))
    #expect(response.status == .success)
    await server.stop()
  }

  @Test func aLiveServerIsNotReplaced() async throws {
    let directory = SocketDirectory()
    let first = IPCServer(path: directory.socket, handler: echo)
    try first.start()
    let second = IPCServer(path: directory.socket, handler: echo)
    #expect(throws: IPCError.alreadyRunning) { try second.start() }
    let response = try await IPCClient(path: directory.socket).send(
      Request(id: "a", command: .ping))
    #expect(response.status == .success)
    await first.stop()
  }

  @Test func aWedgedHandlerIsAnsweredWithInternalAndFreesItsSlot() async throws {
    let directory = SocketDirectory()
    var limits = IPCServer.Limits()
    limits.handlerTimeout = .milliseconds(200)
    limits.maxConnections = 1
    let server = IPCServer(path: directory.socket, limits: limits) { request in
      guard request.command == .status else { return .success(id: request.id) }
      // Ignores cancellation and never returns, like a handler stuck on a lock.
      await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
      return .success(id: request.id)
    }
    try server.start()
    let client = IPCClient(path: directory.socket)
    let wedged = try await client.send(Request(id: "w", command: .status))
    #expect(wedged.code == .internalError)
    let next = try await client.send(Request(id: "n", command: .ping))
    #expect(next.status == .success)
    await server.stop()
  }

  @Test func stopDoesNotWaitForAWedgedHandler() async throws {
    let directory = SocketDirectory()
    let server = IPCServer(path: directory.socket) { request in
      await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
      return .success(id: request.id)
    }
    try server.start()
    let pending = Task {
      try? await IPCClient(path: directory.socket).send(Request(id: "a", command: .ping))
    }
    try await Task.sleep(for: .milliseconds(200))
    await server.stop()
    pending.cancel()
    #expect(!FileManager.default.fileExists(atPath: directory.socket.path))
  }

  @Test func aHeldLockMakesStartFailWithoutTouchingTheSocket() async throws {
    let directory = SocketDirectory()
    try SocketPath.prepareDirectory(of: directory.socket)
    let lock = try POSIXSocket.acquireLock(at: directory.socket.path + ".lock")
    let server = IPCServer(path: directory.socket, handler: echo)
    #expect(throws: IPCError.alreadyRunning) { try server.start() }
    close(lock)
    try server.start()
    #expect(
      try await IPCClient(path: directory.socket).send(Request(id: "a", command: .ping)).status
        == .success)
    await server.stop()
  }

  @Test func stopReleasesTheLockAndFailedStartsDoNotKeepIt() async throws {
    let directory = SocketDirectory()
    let first = IPCServer(path: directory.socket, handler: echo)
    try first.start()
    let second = IPCServer(path: directory.socket, handler: echo)
    #expect(throws: IPCError.alreadyRunning) { try second.start() }
    await first.stop()
    try second.start()
    await second.stop()

    try SocketPath.prepareDirectory(of: directory.socket)
    try Data("keep".utf8).write(to: directory.socket)
    #expect(throws: IPCError.self) { try IPCServer(path: directory.socket, handler: echo).start() }
    try FileManager.default.removeItem(at: directory.socket)
    let again = IPCServer(path: directory.socket, handler: echo)
    try again.start()
    await again.stop()
  }

  @Test func stopLeavesASocketItDidNotBind() async throws {
    let directory = SocketDirectory()
    let server = IPCServer(path: directory.socket, handler: echo)
    try server.start()
    unlink(directory.socket.path)
    let other = try POSIXSocket.makeSocket()
    defer { close(other) }
    try POSIXSocket.bind(other, to: directory.socket.path)
    await server.stop()
    #expect(FileManager.default.fileExists(atPath: directory.socket.path))
  }

  @Test func aRegularFileAtTheSocketPathIsNeverRemoved() throws {
    let directory = SocketDirectory()
    try SocketPath.prepareDirectory(of: directory.socket)
    try Data("keep".utf8).write(to: directory.socket)
    let server = IPCServer(path: directory.socket, handler: echo)
    #expect(throws: IPCError.self) { try server.start() }
    #expect(FileManager.default.fileExists(atPath: directory.socket.path))
  }

  @Test func clientReportsAnAbsentOrDeadServer() async throws {
    let directory = SocketDirectory()
    let client = IPCClient(path: directory.socket)
    await #expect(throws: IPCError.appNotRunning) {
      try await client.send(Request(id: "a", command: .ping))
    }
    try SocketPath.prepareDirectory(of: directory.socket)
    let dead = try POSIXSocket.makeSocket()
    try POSIXSocket.bind(dead, to: directory.socket.path)
    close(dead)
    await #expect(throws: IPCError.appNotRunning) {
      try await client.send(Request(id: "a", command: .ping))
    }
  }

  @Test func clientTimesOutOnASlowHandler() async throws {
    let directory = SocketDirectory()
    let server = IPCServer(path: directory.socket) { request in
      try? await Task.sleep(for: .seconds(5))
      return .success(id: request.id)
    }
    try server.start()
    let client = IPCClient(path: directory.socket, responseTimeout: .milliseconds(200))
    await #expect(throws: IPCError.timedOut) {
      try await client.send(Request(id: "a", command: .ping))
    }
    await server.stop()
  }

  @Test func manyClientsAtOnceAllGetTheirOwnAnswer() async throws {
    let directory = SocketDirectory()
    let server = IPCServer(path: directory.socket, handler: echo)
    try server.start()
    let path = directory.socket
    let ids = try await withThrowingTaskGroup(of: String.self) { group in
      for index in 0..<20 {
        group.addTask {
          let response = try await IPCClient(path: path).send(
            Request(id: "c\(index)", command: .ping))
          return response.id
        }
      }
      var seen: [String] = []
      for try await id in group { seen.append(id) }
      return seen
    }
    #expect(Set(ids) == Set((0..<20).map { "c\($0)" }))
    await server.stop()
  }

  @Test func overlongPathsAreRejected() throws {
    let long = URL(fileURLWithPath: "/tmp/" + String(repeating: "a", count: 120) + "/app.sock")
    #expect(throws: IPCError.pathTooLong) { try SocketPath.validate(long) }
    let server = IPCServer(path: long, handler: echo)
    #expect(throws: IPCError.pathTooLong) { try server.start() }
  }

  @Test func theDefaultPathSitsNextToTheHistoryDatabase() {
    let support = URL(fileURLWithPath: "/Users/someone/Library/Application Support")
    #expect(
      SocketPath.default(applicationSupport: support).path
        == "/Users/someone/Library/Application Support/ntfy-mac/app.sock")
  }

  /// Writes raw bytes and returns the first response line.
  private func rawExchange(_ socket: URL, _ bytes: Data) async throws -> Data {
    let descriptor = try POSIXSocket.makeSocket()
    defer { close(descriptor) }
    #expect(try POSIXSocket.connect(descriptor, to: socket.path) == 0)
    try await POSIXSocket.writeAll(descriptor, bytes, timeout: .seconds(2))
    return try await POSIXSocket.readLine(descriptor, limit: 1 << 16, timeout: .seconds(5))
  }
}
