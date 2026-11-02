import Foundation
import NtfyCore
import NtfyTesting

actor SinkRecorder {
  private(set) var events: [StreamEvent] = []
  func record(_ event: StreamEvent) { events.append(event) }
}

/// A supervisor wired to fakes, with helpers to wait for it deterministically: no real sleeping,
/// only a bounded yield loop.
struct SupervisorRig {
  let clock = FakeClock()
  let stream = ManualMessageStream()
  let poller: ScriptedMessagePoller
  let topics: ScriptedTopicSource
  let cursor: InMemoryCursorStore
  let history = InMemoryHistoryStore()
  let poster: RecordingNotificationPoster
  let events = ManualSystemEvents()
  let sink = SinkRecorder()
  let supervisor: StreamSupervisor
  /// Sleepers of a settled connection: the machine's timer, plus topic rediscovery.
  private let settledSleepers: Int

  init(
    cursor: String? = nil,
    polls: [ScriptedMessagePoller.Response] = [],
    topics: ScriptedTopicSource = ScriptedTopicSource(topics: ["alpha"]),
    customTopics: (any TopicSource)? = nil,
    customPoller: (any MessagePoller)? = nil,
    poster: RecordingNotificationPoster = RecordingNotificationPoster(),
    configure: (inout StreamSupervisor.Options) -> Void = { _ in }
  ) {
    let poller = ScriptedMessagePoller(polls)
    let cursorStore = InMemoryCursorStore(cursor)
    self.poller = poller
    self.topics = topics
    self.cursor = cursorStore
    self.poster = poster
    var options = StreamSupervisor.Options()
    options.jitter = { 1 }
    let sink = self.sink
    options.sink = { event in await sink.record(event) }
    configure(&options)
    settledSleepers = options.selection.override == nil ? 2 : 1
    supervisor = StreamSupervisor(
      ports: StreamSupervisor.Ports(
        stream: stream, poller: customPoller ?? poller, topics: customTopics ?? topics,
        cursor: cursorStore, history: history,
        poster: poster, systemEvents: events, clock: clock),
      options: options)
  }

  // MARK: Waiting

  /// Polls `condition` between yields, up to a hard cap.
  func eventually(_ condition: () async -> Bool) async -> Bool {
    for _ in 0..<200_000 {
      if await condition() { return true }
      await Task.yield()
    }
    return false
  }

  /// Gives every runnable task a chance to run; for asserting that nothing more happens.
  func settle() async {
    for _ in 0..<3000 { await Task.yield() }
  }

  func waitFor(_ status: ConnectionStatus) async -> Bool {
    await eventually { await supervisor.currentStatus == status }
  }

  func waitForCalls(_ count: Int) async -> Bool {
    await eventually { stream.calls.count >= count }
  }

  func waitForSleepers(_ count: Int) async -> Bool {
    await eventually { clock.sleeperCount == count }
  }

  /// Waits for a backoff and returns its deadline and attempt.
  func waitForBackoff() async -> (until: Date, attempt: Int)? {
    var found: (until: Date, attempt: Int)?
    _ = await eventually {
      if case .backingOff(let until, let attempt) = await supervisor.currentStatus {
        found = (until, attempt)
        return true
      }
      return false
    }
    return found
  }

  // MARK: Driving

  /// Starts (once) and opens the `index`th connection, and waits until its timers are
  /// registered with the clock: advancing before that would measure the wait from a later "now".
  @discardableResult
  func connect(connection index: Int = 1) async -> Bool {
    if index == 1 { await supervisor.start() }
    guard await waitForCalls(index) else { return false }
    stream.send(.open)
    guard await waitFor(.connected) else { return false }
    return await waitForSleepers(settledSleepers)
  }

  func advance(_ seconds: Double) async {
    clock.advance(by: .seconds(seconds))
    await settle()
  }

  /// Passes `seconds` in 15 s steps with a keepalive each. The small step leaves the 90 s
  /// watchdog room even if the supervisor is slow to process a keepalive.
  func idle(for seconds: Int) async {
    for _ in 0..<(seconds / 15) {
      await advance(15)
      stream.send(.keepalive)
      await settle()
    }
  }

  /// The fake clock's default start, so messages can be built before the rig exists.
  static let epoch = Date(timeIntervalSince1970: 1_700_000_000)

  static func message(_ id: String, topic: String = "alpha", age: TimeInterval = 0) -> NtfyMessage {
    NtfyMessage(id: id, topic: topic, time: epoch.addingTimeInterval(-age), body: "body \(id)")
  }

  func message(_ id: String, topic: String = "alpha", age: TimeInterval = 0) -> NtfyMessage {
    Self.message(id, topic: topic, age: age)
  }
}
