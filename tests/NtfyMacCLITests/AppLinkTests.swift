import Foundation
import NtfyCore
import NtfyIPC
import Testing

@testable import NtfyMacCLI

private actor Launches {
  private(set) var count = 0
  func record() { count += 1 }
}

private actor Answers {
  private(set) var calls = 0
  private let notReadyFor: Int
  init(notReadyFor: Int) { self.notReadyFor = notReadyFor }

  func next(_ request: Request) -> Response {
    calls += 1
    return calls <= notReadyFor
      ? .failure(id: request.id, code: .appUnavailable, message: "starting")
      : .success(id: request.id)
  }
}

@Suite struct AppLinkTests {
  private let socket = URL(
    fileURLWithPath: "/tmp/ntfylink-\(UUID().uuidString.prefix(8))/app.sock")
  private let app = URL(fileURLWithPath: "/tmp/NtfyMac.app")
  private let ping = Request(id: "1", command: .ping)

  private func serve() -> IPCServer {
    IPCServer(path: socket) { .success(id: $0.id) }
  }

  private func cleanup() {
    try? FileManager.default.removeItem(at: socket.deletingLastPathComponent())
  }

  @Test func aRunningAppAnswersWithoutALaunch() async throws {
    defer { cleanup() }
    let server = serve()
    try server.start()
    let launches = Launches()
    let link = AppLink(socket: socket, app: app) { _ in
      await launches.record()
      return true
    }
    let response = try await link.send(ping)
    #expect(response.status == .success)
    #expect(await launches.count == 0)
    await server.stop()
  }

  @Test func aDownAppIsLaunchedAndRetried() async throws {
    defer { cleanup() }
    let server = serve()
    let launches = Launches()
    let link = AppLink(socket: socket, app: app) { _ in
      await launches.record()
      try? await Task.sleep(for: .milliseconds(100))
      return (try? server.start()) != nil
    }
    let response = try await link.send(ping)
    #expect(response.status == .success)
    #expect(await launches.count == 1)
    await server.stop()
  }

  @Test func aSocketThatAnswersNotReadyAfterAColdLaunchIsRetried() async throws {
    defer { cleanup() }
    let answers = Answers(notReadyFor: 3)
    let server = IPCServer(path: socket) { await answers.next($0) }
    let link = AppLink(socket: socket, app: app) { _ in (try? server.start()) != nil }
    let response = try await link.send(ping)
    #expect(response.status == .success)
    #expect(await answers.calls == 4)
    await server.stop()
  }

  @Test func notReadyForeverReturnsTheAppsAnswerAtTheDeadline() async throws {
    defer { cleanup() }
    let answers = Answers(notReadyFor: .max)
    let server = IPCServer(path: socket) { await answers.next($0) }
    let link = AppLink(
      socket: socket, app: app, launch: { _ in (try? server.start()) != nil },
      launchTimeout: .milliseconds(1500))
    let response = try await link.send(ping)
    #expect(response.code == .appUnavailable)
    #expect(await answers.calls > 1)
    await server.stop()
  }

  @Test func notReadyFromARunningAppIsNotRetried() async throws {
    defer { cleanup() }
    let answers = Answers(notReadyFor: .max)
    let server = IPCServer(path: socket) { await answers.next($0) }
    try server.start()
    let launches = Launches()
    let link = AppLink(socket: socket, app: app) { _ in
      await launches.record()
      return true
    }
    let response = try await link.send(ping)
    #expect(response.code == .appUnavailable)
    #expect(await answers.calls == 1)
    #expect(await launches.count == 0)
    await server.stop()
  }

  @Test func anAppThatNeverComesUpIsUnavailable() async {
    defer { cleanup() }
    let link = AppLink(
      socket: socket, app: app, launch: { _ in true }, launchTimeout: .milliseconds(200))
    await #expect(throws: NtfyError.appUnavailable) { try await link.send(ping) }
  }

  @Test func aLaunchThatFailsIsUnavailable() async {
    let link = AppLink(socket: socket, app: app, launch: { _ in false })
    await #expect(throws: NtfyError.appUnavailable) { try await link.send(ping) }
  }

  @Test func aDownAppIsNotLaunchedWhenLaunchingIsOff() async {
    defer { cleanup() }
    let launches = Launches()
    let link = AppLink(socket: socket, app: app) { _ in
      await launches.record()
      return true
    }
    await #expect(throws: NtfyError.appUnavailable) { try await link.send(ping, launch: false) }
    #expect(await launches.count == 0)
  }

  @Test func noEnclosingAppMeansUnavailable() async {
    let link = AppLink(socket: socket, app: nil, launch: { _ in true })
    await #expect(throws: NtfyError.appUnavailable) { try await link.send(ping) }
  }
}
