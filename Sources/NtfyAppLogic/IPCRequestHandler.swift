import Foundation
import NtfyCore
import NtfyIPC

/// Answers the CLI's requests. It asks for the pipeline on every request instead of holding one,
/// so it keeps working across pipeline rebuilds; commands that need a pipeline answer
/// `app-unavailable` while there is none.
public struct IPCRequestHandler: Sendable {
  /// Local messages live under their own topic, so they never collide with a server's.
  public static let localTopic = "local"

  public typealias PipelineProvider = @Sendable () async -> PipelineHandles?

  private let pipeline: PipelineProvider
  private let config: any ConfigStore
  private let permissions: any NotificationPermissionProviding
  private let clock: any NtfyCore.Clock
  private let loginItem: any LoginItemControlling
  private let meeting: (any MeetingStateProviding)?
  private let log: @Sendable (String) -> Void

  public init(
    pipeline: @escaping PipelineProvider, config: any ConfigStore,
    permissions: any NotificationPermissionProviding, clock: any NtfyCore.Clock,
    loginItem: any LoginItemControlling, meeting: (any MeetingStateProviding)? = nil,
    log: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.pipeline = pipeline
    self.config = config
    self.permissions = permissions
    self.clock = clock
    self.loginItem = loginItem
    self.meeting = meeting
    self.log = log
  }

  public func handle(_ request: Request) async -> Response {
    switch request.command {
    case .ping: return .success(id: request.id)
    case .status: return await status(request)
    case .permission: return await permission(request)
    case .reconnect: return await reconnect(request)
    case .notify: return await notify(request)
    case .ack: return await ack(request)
    case .remind: return await remind(request)
    case .delete: return await delete(request)
    case .ackAll: return await ackAll(request)
    case .loginItem: return loginItemResponse(request)
    }
  }

  // MARK: Reads

  private func status(_ request: Request) async -> Response {
    let connection = await pipeline()?.supervisor?.currentStatus ?? .stopped
    let result = StatusResult(
      connection: connection.ipcName, pausedUntil: await activePause(),
      appVersion: Version.current, permission: await permissions.current().summary,
      meeting: await meetingSummary())
    return .success(id: request.id, result: ResultPayload(status: result))
  }

  /// What holds notifications back now because of a meeting: the override or, with the mode on,
  /// the detection.
  private func meetingSummary() async -> MeetingSummary {
    let settings = (try? await config.load().meeting) ?? MeetingSettings()
    let now = clock.now()
    let state = settings.effectiveState(detected: await meeting?.current() ?? .inactive, at: now)
    return MeetingSummary(
      active: state.isActive, reason: state.reason?.code, detail: state.reason?.detail,
      presenting: settings.isPresenting(at: now))
  }

  private func permission(_ request: Request) async -> Response {
    let summary = await permissions.current().summary
    return .success(id: request.id, result: ResultPayload(permission: summary))
  }

  private func activePause() async -> Date? {
    guard let until = try? await config.load().pausedUntil, until > clock.now() else { return nil }
    return until
  }

  // MARK: Actions

  private func reconnect(_ request: Request) async -> Response {
    guard let supervisor = await pipeline()?.supervisor else {
      return unavailable(request, "no server is connected; run `ntfy-mac setup`")
    }
    await supervisor.restart()
    return .success(id: request.id)
  }

  private func notify(_ request: Request) async -> Response {
    guard let payload = request.notify else {
      return badRequest(request, "notify needs a non-empty body")
    }
    let accepted: NotifyValidation.Accepted
    switch NotifyValidation.check(payload) {
    case .failure(let rejection): return badRequest(request, rejection.message)
    case .success(let value): accepted = value
    }
    guard await permissions.current().isUsable else {
      return .failure(
        id: request.id, code: .permissionDenied,
        message: "notifications are not allowed for ntfy-mac; see `ntfy-mac doctor`")
    }
    guard let messages = await pipeline()?.messages else { return unavailable(request) }
    let paused = await activePause() != nil
    let message = NtfyMessage(
      id: "local-\(UUID().uuidString.lowercased())", topic: Self.localTopic, time: clock.now(),
      title: accepted.title, body: payload.body, priority: Priority(clamping: payload.priority),
      tags: payload.tags, click: payload.clickURL)
    do throws(NtfyError) {
      try await messages.post(message, dismissAfter: accepted.dismissAfter)
    } catch {
      return internalError(request, "notify", error)
    }
    return .success(id: request.id, result: ResultPayload(notify: NotifyResult(posted: !paused)))
  }

  private func ack(_ request: Request) async -> Response {
    guard let target = request.ack else { return badRequest(request, "ack needs topic and id") }
    guard let messages = await pipeline()?.messages else { return unavailable(request) }
    do throws(NtfyError) {
      let found = try await messages.acknowledge(topic: target.topic, id: target.id)
      return found ? .success(id: request.id) : notFound(request, target.topic, target.id)
    } catch {
      return internalError(request, "ack", error)
    }
  }

  private func ackAll(_ request: Request) async -> Response {
    guard let messages = await pipeline()?.messages else { return unavailable(request) }
    do throws(NtfyError) {
      let count = try await messages.acknowledgeAll(topic: request.ackAll?.topic)
      return .success(
        id: request.id, result: ResultPayload(ackAll: AckAllResult(acknowledged: count)))
    } catch {
      return internalError(request, "ack-all", error)
    }
  }

  private func remind(_ request: Request) async -> Response {
    guard let target = request.remind else {
      return badRequest(request, "remind needs topic, id and until")
    }
    guard let messages = await pipeline()?.messages else { return unavailable(request) }
    do throws(NtfyError) {
      let found = try await messages.remind(topic: target.topic, id: target.id, until: target.until)
      return found ? .success(id: request.id) : notFound(request, target.topic, target.id)
    } catch {
      return internalError(request, "remind", error)
    }
  }

  private func delete(_ request: Request) async -> Response {
    guard let target = request.delete else { return badRequest(request, "delete needs a topic") }
    guard let messages = await pipeline()?.messages else { return unavailable(request) }
    guard let id = target.id else {
      let count = await messages.deleteAll(topic: target.topic)
      return .success(id: request.id, result: ResultPayload(delete: DeleteResult(deleted: count)))
    }
    guard await messages.delete(topic: target.topic, id: id) else {
      return notFound(request, target.topic, id)
    }
    return .success(id: request.id, result: ResultPayload(delete: DeleteResult(deleted: 1)))
  }

  /// Reads the registration, or changes it first when the request says so.
  private func loginItemResponse(_ request: Request) -> Response {
    var state = loginItem.state()
    let action = request.loginItem?.action ?? .status
    if action != .status {
      do throws(NtfyError) {
        state = try loginItem.setEnabled(action == .enable)
      } catch {
        return internalError(request, "login-item", error)
      }
    }
    return .success(
      id: request.id, result: ResultPayload(loginItem: LoginItemResult(state: state.rawValue)))
  }

  // MARK: Helpers

  private func unavailable(
    _ request: Request, _ message: String = "ntfy-mac is restarting; try again in a moment"
  ) -> Response {
    .failure(id: request.id, code: .appUnavailable, message: message)
  }

  private func badRequest(_ request: Request, _ message: String) -> Response {
    .failure(id: request.id, code: .badRequest, message: message)
  }

  private func notFound(_ request: Request, _ topic: String, _ id: String) -> Response {
    .failure(id: request.id, code: .notFound, message: "no message \(topic)/\(id) in the history")
  }

  private func internalError(_ request: Request, _ what: String, _ error: NtfyError) -> Response {
    log("\(what) failed: \(String(describing: error))")
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
