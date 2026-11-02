import AppKit
import Foundation
import NtfyCore
import NtfyIPC

/// The CLI's channel to the running app: sends a request over the socket and, when nobody
/// listens, launches the enclosing `NtfyMac.app` through LaunchServices and retries for a
/// bounded time. Every failure to reach the app is `NtfyError.appUnavailable`.
struct AppLink: Sendable {
  /// Opens the app bundle; false when it could not be launched.
  typealias Launcher = @Sendable (URL) async -> Bool

  private let socket: URL
  private let app: URL?
  private let launch: Launcher
  private let launchTimeout: Duration
  private let client: IPCClient

  init(
    socket: URL = AppLink.defaultSocket, app: URL? = AppBundle.enclosing(),
    launch: @escaping Launcher = AppLink.openWithLaunchServices,
    launchTimeout: Duration = .seconds(10), responseTimeout: Duration = .seconds(10)
  ) {
    self.socket = socket
    self.app = app
    self.launch = launch
    self.launchTimeout = launchTimeout
    client = IPCClient(path: socket, responseTimeout: responseTimeout)
  }

  static var defaultSocket: URL {
    let support =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser.appending(
        path: "Library/Application Support", directoryHint: .isDirectory)
    return SocketPath.default(applicationSupport: support)
  }

  /// The app's answer, which may itself be an error response (`Response.status == .error`).
  func send(_ request: Request) async throws(NtfyError) -> Response {
    do throws(IPCError) {
      return try await client.send(request)
    } catch .appNotRunning {
      return try await launchAndRetry(request)
    } catch {
      throw Self.map(error)
    }
  }

  private func launchAndRetry(_ request: Request) async throws(NtfyError) -> Response {
    guard let app, await launch(app) else { throw .appUnavailable }
    let deadline = ContinuousClock.now.advanced(by: launchTimeout)
    var delay = Duration.milliseconds(20)
    while ContinuousClock.now < deadline {
      do throws(IPCError) {
        return try await client.send(request)
      } catch .appNotRunning {
        try? await Task.sleep(for: delay)
        delay = min(delay * 3 / 2, .milliseconds(250))
      } catch {
        throw Self.map(error)
      }
    }
    throw .appUnavailable
  }

  private static func map(_ error: IPCError) -> NtfyError {
    switch error {
    case .unsupportedProtocolVersion(let version):
      .invalidResponse("the app speaks protocol \(version); update ntfy-mac")
    case .malformedFrame, .frameTooLarge:
      .invalidResponse("the app sent a malformed response")
    case .pathTooLong, .appNotRunning, .alreadyRunning, .timedOut, .connectionClosed, .cancelled,
      .system:
      .appUnavailable
    }
  }

  static let openWithLaunchServices: Launcher = { url in
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = false
    do {
      _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
      return true
    } catch {
      return false
    }
  }
}

/// Finds the `.app` this executable ships in.
enum AppBundle {
  /// The enclosing `.app`, resolving symlinks (the CLI is usually reached through a link on
  /// the PATH); nil when the executable does not live inside one.
  static func enclosing() -> URL? {
    var size: UInt32 = 4096
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    guard let path = String(validating: bytes, as: UTF8.self) else { return nil }
    var url = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    while url.path != "/" {
      if url.pathExtension == "app" { return url }
      url.deleteLastPathComponent()
    }
    return nil
  }
}
