import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Synchronization

/// A pipeline source the test swaps by hand.
final class ManualPipelineSource: PipelineSource {
  private let handles = Mutex<PipelineHandles?>(nil)
  private let signal = ChangeSignal()

  func set(_ new: PipelineHandles?) {
    handles.withLock { $0 = new }
    signal.fire()
  }

  func current() async -> PipelineHandles? { handles.withLock { $0 } }
  func rebuilds() -> AsyncStream<Void> { signal.stream() }
}

/// One pipeline over the in-memory fakes. With `connected` it has a supervisor on a manual
/// stream, like a configured server.
struct PipelineFixture {
  let clock = FakeClock()
  let poster = RecordingNotificationPoster()
  let history: InMemoryHistoryStore
  let config: InMemoryConfigStore
  let delivery: DeliveryService
  let stream = ManualMessageStream()
  let supervisor: StreamSupervisor?
  let attachments = StubAttachmentFetcher()
  let handles: PipelineHandles

  init(withServer: Bool = false, config initial: Config = Config()) {
    history = InMemoryHistoryStore(clock: clock)
    config = InMemoryConfigStore(initial)
    delivery = DeliveryService(
      poster: poster, history: history, inbox: history, config: config, clock: clock)
    if withServer {
      supervisor = StreamSupervisor(
        ports: StreamSupervisor.Ports(
          stream: stream, poller: ScriptedMessagePoller(),
          topics: ScriptedTopicSource(topics: ["alerts"]),
          cursor: InMemoryCursorStore(), history: history, delivery: RecordingDelivery(),
          systemEvents: ManualSystemEvents(), clock: clock),
        options: StreamSupervisor.Options())
    } else {
      supervisor = nil
    }
    handles = PipelineHandles(
      store: history, delivery: delivery, supervisor: supervisor, attachments: attachments)
  }

  func message(
    _ id: String, topic: String = "alerts", age: TimeInterval = 0, title: String? = nil,
    priority: Priority = .default
  ) -> NtfyMessage {
    NtfyMessage(
      id: id, topic: topic, time: clock.now().addingTimeInterval(-age), title: title,
      body: "body \(id)", priority: priority)
  }

  func seed(_ ids: [String], priority: Priority = .default) async {
    for (index, id) in ids.enumerated() {
      _ = try? await history.append(
        message(id, age: Double(ids.count - index), priority: priority))
    }
  }
}

/// The model over a manual source and an in-memory config, with a bounded wait.
@MainActor
struct ModelRig {
  let source = ManualPipelineSource()
  let permission = InMemoryNotificationPermission(.allowed)
  let configChanges = ChangeSignal()
  let meeting = ManualMeetingState()
  let pipeline: PipelineFixture
  let model: AppModel

  init(
    pipeline: PipelineFixture = PipelineFixture(), recentLimit: Int = 8,
    calendar: Calendar = Calendar(identifier: .gregorian)
  ) {
    self.pipeline = pipeline
    source.set(pipeline.handles)
    let signal = configChanges
    model = AppModel(
      source: source, meeting: meeting, config: pipeline.config, permissions: permission,
      clock: pipeline.clock,
      configChanges: { signal.stream() }, calendar: calendar, recentLimit: recentLimit)
  }

  /// Polls `condition` between yields, up to a hard cap.
  func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200_000 {
      if condition() { return true }
      await Task.yield()
    }
    return false
  }
}
