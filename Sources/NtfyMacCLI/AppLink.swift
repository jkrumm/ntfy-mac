import AppKit
import Foundation
import NtfyCore
import NtfyIPC
import NtfyPlatform

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
  private let clock: any NtfyCore.Clock
  private let client: IPCClient

  init(
    socket: URL = AppLink.defaultSocket, app: URL? = AppBundle.enclosing(),
    launch: @escaping Launcher = AppLink.openWithLaunchServices,
    launchTimeout: Duration = .seconds(10), responseTimeout: Duration = .seconds(10),
    clock: any NtfyCore.Clock = SystemClock()
  ) {
    self.socket = socket
    self.app = app
    self.launch = launch
    self.launchTimeout = launchTimeout
    self.clock = clock
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
  /// With `launch` false a down app is `appUnavailable` at once and nothing is started, for
  /// read-only callers like `doctor`.
  func send(_ request: Request, launch: Bool = true) async throws(NtfyError) -> Response {
    do throws(IPCError) {
      return try await client.send(request)
    } catch .appNotRunning {
      guard launch else { throw .appUnavailable }
      return try await launchAndRetry(request)
    } catch {
      throw Self.map(error)
    }
  }

  /// After a cold launch the socket can exist before the pipeline does, so an `app-unavailable`
  /// answer is retried too; if it is still that at the deadline, it is returned as it is.
  private func launchAndRetry(_ request: Request) async throws(NtfyError) -> Response {
    guard let app, await launch(app) else { throw .appUnavailable }
    let deadline = clock.now().addingTimeInterval(launchTimeout.timeInterval)
    var delay = Duration.milliseconds(20)
    var notReady: Response?
    while clock.now() < deadline {
      do throws(IPCError) {
        let response = try await client.send(request)
        guard response.code == .appUnavailable else { return response }
        notReady = response
      } catch .appNotRunning {
        // Nothing listens yet.
      } catch {
        throw Self.map(error)
      }
      try? await clock.sleep(for: delay)
      delay = min(delay * 3 / 2, .milliseconds(250))
    }
    guard let notReady else { throw .appUnavailable }
    return notReady
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

extension Duration {
  fileprivate var timeInterval: TimeInterval {
    TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1e18
  }
}

/// What the commands need from the app, so they can be tested without a socket.
protocol AppControlling: Sendable {
  func send(_ request: Request, launch: Bool) async throws(NtfyError) -> Response
}

extension AppLink: AppControlling {}

/// Finds the `.app` this executable ships in.
enum AppBundle {
  /// The running executable, symlinks resolved (the CLI is usually reached through a link on
  /// the PATH); nil when the system cannot say.
  static func executable() -> URL? {
    var size: UInt32 = 4096
    var buffer = [CChar](repeating: 0, count: Int(size))
    guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    guard let path = String(validating: bytes, as: UTF8.self) else { return nil }
    return URL(fileURLWithPath: path).resolvingSymlinksInPath()
  }

  /// The enclosing `.app`; nil when the executable does not live inside one.
  static func enclosing() -> URL? {
    guard let url = executable() else { return nil }
    return enclosing(of: url)
  }

  /// The `.app` that contains `executable`; nil when there is none.
  static func enclosing(of executable: URL) -> URL? {
    var url = executable
    while url.path != "/" {
      if url.pathExtension == "app" { return url }
      url.deleteLastPathComponent()
    }
    return nil
  }
}
