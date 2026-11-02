import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyIPC
import NtfyTesting

/// The socket handler over the in-memory fakes, the way the app wires it for a pipeline with no
/// server: no configuration, no stream.
struct HandlerRig {
  let clock = FakeClock()
  let poster = RecordingNotificationPoster()
  let history: InMemoryHistoryStore
  let config: InMemoryConfigStore
  let permission: InMemoryNotificationPermission
  let service: DeliveryService
  let handler: IPCRequestHandler

  init(
    config initial: Config = Config(), permission: NotificationPermission = .allowed,
    pipelineAvailable: Bool = true
  ) {
    history = InMemoryHistoryStore(clock: clock)
    config = InMemoryConfigStore(initial)
    self.permission = InMemoryNotificationPermission(permission)
    service = DeliveryService(
      poster: poster, history: history, inbox: history, config: config, clock: clock)
    let handles = PipelineHandles(store: history, delivery: service, supervisor: nil)
    handler = IPCRequestHandler(
      pipeline: { pipelineAvailable ? handles : nil }, config: config,
      permissions: self.permission, clock: clock, loginItem: InMemoryLoginItem())
  }

  func send(_ request: Request) async -> Response { await handler.handle(request) }

  func notify(_ payload: NotifyPayload) async -> Response {
    await send(Request(id: "1", command: .notify, notify: payload))
  }

  func waitForPosts(_ count: Int) async -> Bool {
    for _ in 0..<200_000 {
      if await poster.posted.count >= count { return true }
      await Task.yield()
    }
    return false
  }
}
