import Foundation
import NtfyCore
import NtfyIPC
import NtfyPlatform

/// Answers the CLI's requests. It holds the controller, not a pipeline, so it keeps working
/// across pipeline rebuilds; commands that need the pipeline answer `app-unavailable` while
/// there is none.
struct AppIPCHandler: Sendable {
  let controller: AppController
  let config: FileConfigStore
  let permissions: any NotificationPermissionProviding
  let clock: SystemClock
  private let log = Log.logger(.ipc)

  init(
    controller: AppController, config: FileConfigStore,
    permissions: any NotificationPermissionProviding, clock: SystemClock
  ) {
    self.controller = controller
    self.config = config
    self.permissions = permissions
    self.clock = clock
  }

  func handle(_ request: Request) async -> Response {
    switch request.command {
    case .ping: return .success(id: request.id)
    case .status: return await status(request)
    case .permission: return await permission(request)
    case .reconnect: return await reconnect(request)
    case .notify: return await notify(request)
    case .ack: return await ack(request)
    case .remind: return await remind(request)
    }
  }

  // MARK: Reads

  private func status(_ request: Request) async -> Response {
    let connection = await controller.runningPipeline()?.connectionStatus() ?? .stopped
    let pausedUntil = await activePause()
    let permission = await permissions.current().summary
    let result = StatusResult(
      connection: connection.ipcName, pausedUntil: pausedUntil, appVersion: Version.current,
      permission: permission)
    return .success(id: request.id, result: ResultPayload(status: result))
  }

  private func permission(_ request: Request) async -> Response {
    let summary = await permissions.current().summary
    return .success(id: request.id, result: ResultPayload(permission: summary))
  }

  private func activePause() async -> Date? {
    guard let until = await config.load().pausedUntil, until > clock.now() else { return nil }
    return until
  }

  // MARK: Actions

  private func reconnect(_ request: Request) async -> Response {
    guard let pipeline = await controller.runningPipeline() else { return unavailable(request) }
    await pipeline.reconnect()
    return .success(id: request.id)
  }

  private func notify(_ request: Request) async -> Response {
    guard let payload = request.notify, !payload.body.isEmpty else {
      return badRequest(request, "notify needs a non-empty body")
    }
    guard await permissions.current().isUsable else {
      return .failure(
        id: request.id, code: .permissionDenied,
        message: "notifications are not allowed for ntfy-mac; see `ntfy-mac doctor`")
    }
    guard let pipeline = await controller.runningPipeline() else { return unavailable(request) }
    let paused = await activePause() != nil
    do throws(NtfyError) {
      try await pipeline.postLocal(
        Self.message(from: payload, at: clock.now()), dismissAfter: payload.dismissAfterSeconds)
    } catch {
      return internalError(request, "notify", error)
    }
    return .success(
      id: request.id, result: ResultPayload(notify: NotifyResult(posted: !paused)))
  }

  private func ack(_ request: Request) async -> Response {
    guard let target = request.ack else { return badRequest(request, "ack needs topic and id") }
    guard let pipeline = await controller.runningPipeline() else { return unavailable(request) }
    do throws(NtfyError) {
      let found = try await pipeline.acknowledge(topic: target.topic, id: target.id)
      return found ? .success(id: request.id) : notFound(request, target.topic, target.id)
    } catch {
      return internalError(request, "ack", error)
    }
  }

  private func remind(_ request: Request) async -> Response {
    guard let target = request.remind else {
      return badRequest(request, "remind needs topic, id and until")
    }
    guard let pipeline = await controller.runningPipeline() else { return unavailable(request) }
    do throws(NtfyError) {
      let found = try await pipeline.remind(topic: target.topic, id: target.id, until: target.until)
      return found ? .success(id: request.id) : notFound(request, target.topic, target.id)
    } catch {
      return internalError(request, "remind", error)
    }
  }

  // MARK: Helpers

  /// Local messages live under their own topic, so they never collide with a server's.
  static let localTopic = "local"

  private static func message(from payload: NotifyPayload, at time: Date) -> NtfyMessage {
    NtfyMessage(
      id: "local-\(UUID().uuidString.lowercased())", topic: localTopic, time: time,
      title: payload.title.flatMap { $0.isEmpty ? nil : $0 }, body: payload.body,
      priority: Priority(clamping: payload.priority), tags: payload.tags,
      click: payload.clickURL)
  }

  private func unavailable(_ request: Request) -> Response {
    .failure(
      id: request.id, code: .appUnavailable,
      message: "ntfy-mac is not configured or is restarting")
  }

  private func badRequest(_ request: Request, _ message: String) -> Response {
    .failure(id: request.id, code: .badRequest, message: message)
  }

  private func notFound(_ request: Request, _ topic: String, _ id: String) -> Response {
    .failure(id: request.id, code: .notFound, message: "no message \(topic)/\(id) in the history")
  }

  private func internalError(_ request: Request, _ what: String, _ error: NtfyError) -> Response {
    log.error("\(what, privacy: .public) failed: \(String(describing: error), privacy: .public)")
    return .failure(id: request.id, code: .internalError, message: "\(what) failed")
  }
}

extension NotificationPermission {
  fileprivate var summary: PermissionSummary {
    PermissionSummary(
      usable: isUsable, problems: problems.map { PermissionIssue(code: $0.code, hint: $0.hint) })
  }
}

extension ConnectionStatus {
  /// The stable lowercase name `ntfy-mac status` reports.
  fileprivate var ipcName: String {
    switch self {
    case .stopped: "stopped"
    case .connecting: "connecting"
    case .connected: "connected"
    case .backingOff: "backing-off"
    case .offline: "offline"
    case .paused: "paused"
    case .halted: "halted"
    }
  }
}
