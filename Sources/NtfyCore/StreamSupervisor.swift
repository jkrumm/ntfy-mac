import Foundation

/// Receives the stream events that are not messages (`messageDelete`, `messageClear`), verbatim.
public typealias StreamEventSink = @Sendable (StreamEvent) async -> Void

/// Keeps one subscription alive: resolves topics, catches up on what was missed, holds the
/// stream, and reconnects as `ReconnectMachine` decides. Nothing it does throws out of it; every
/// failure becomes a `ConnectionStatus`.
///
/// Delivery: every message reaches history at least once (the cursor only passes stored
/// messages) and is handed to `Delivering` once (see `MessageIngest`).
public actor StreamSupervisor {
  /// Everything the supervisor talks to.
  public struct Ports: Sendable {
    public let stream: any MessageStream
    public let poller: any MessagePoller
    public let topics: any TopicSource
    public let cursor: any CursorStore
    public let history: any HistoryStore
    public let delivery: any Delivering
    public let systemEvents: any SystemEvents
    public let clock: any Clock

    public init(
      stream: any MessageStream, poller: any MessagePoller, topics: any TopicSource,
      cursor: any CursorStore, history: any HistoryStore, delivery: any Delivering,
      systemEvents: any SystemEvents, clock: any Clock
    ) {
      self.stream = stream
      self.poller = poller
      self.topics = topics
      self.cursor = cursor
      self.history = history
      self.delivery = delivery
      self.systemEvents = systemEvents
      self.clock = clock
    }
  }

  public struct Options: Sendable {
    public var selection = TopicSelection()
    public var timing = ReconnectMachine.Timing()
    /// Whether the network is assumed up before the first path event arrives.
    public var initiallyOnline = true
    /// How often the account's topics are fetched again while connected.
    public var rediscoveryInterval: Duration = .seconds(30 * 60)
    /// A value in 0...1 used to spread retries.
    public var jitter: @Sendable () -> Double = { Double.random(in: 0...1) }
    public var log: @Sendable (String) -> Void = { _ in }
    /// Called when the supervisor starts; the closure it returns is called when it stops. The app
    /// root passes `ProcessInfo.beginActivity`/`endActivity` here to keep App Nap away.
    public var activity: @Sendable () -> @Sendable () -> Void = { {} }
    public var sink: StreamEventSink?

    public init() {}
  }

  let ports: Ports
  let options: Options
  let ingest: MessageIngest
  let broadcaster = StatusBroadcaster()
  var machine: ReconnectMachine
  var selection: TopicSelection
  var running = false
  var currentTopics: [String] = []
  var connectionID = 0
  var connectionTask: Task<Void, Never>?
  var rediscoveryTask: Task<Void, Never>?
  var systemTask: Task<Void, Never>?
  var timerTask: Task<Void, Never>?
  var timerDeadline: Date?
  var timerGeneration = 0
  var endActivity: (@Sendable () -> Void)?

  public init(ports: Ports, options: Options = Options()) {
    self.ports = ports
    self.options = options
    selection = options.selection
    machine = ReconnectMachine(
      timing: options.timing, online: options.initiallyOnline, jitter: options.jitter)
    ingest = MessageIngest(
      history: ports.history, delivery: ports.delivery, cursor: ports.cursor, log: options.log)
  }

  /// Every status change, starting with the current one. Any number of subscribers.
  public nonisolated var status: AsyncStream<ConnectionStatus> { broadcaster.stream() }

  public var currentStatus: ConnectionStatus { machine.status }

  public func start() {
    guard !running else { return }
    running = true
    endActivity = options.activity()
    let events = ports.systemEvents.events()
    systemTask = Task {
      for await event in events { self.apply(.system(event)) }
    }
    apply(.start)
  }

  /// Cancels everything and returns once no task of the supervisor is left running.
  public func stop() async {
    guard running else { return }
    running = false
    let tasks = [systemTask, connectionTask, rediscoveryTask, timerTask].compactMap { $0 }
    systemTask = nil
    let end = endActivity
    endActivity = nil
    apply(.stop)
    for task in tasks { task.cancel() }
    for task in tasks { await task.value }
    end?()
  }

  /// Leaves a halt (after fixing the credentials, say) and connects now.
  public func restart() {
    guard running else { return }
    apply(.restart)
  }

  /// Applies a new topic selection, which reconnects.
  public func reconfigure(selection new: TopicSelection) {
    guard new != selection else { return }
    selection = new
    guard running else { return }
    apply(.restart)
  }
}

// MARK: - Driving the machine

extension StreamSupervisor {
  func apply(_ input: ReconnectMachine.Input) {
    let command = machine.handle(input, at: ports.clock.now())
    broadcaster.publish(machine.status)
    switch command {
    case .connect: startConnection()
    case .disconnect: cancelConnection()
    case nil: break
    }
    rearmTimer()
  }

  func isCurrent(_ id: Int) -> Bool { id == connectionID && !Task.isCancelled }

  private func startConnection() {
    cancelConnection()
    let id = connectionID
    connectionTask = Task { await self.runConnection(id) }
  }

  private func cancelConnection() {
    connectionID += 1
    connectionTask?.cancel()
    connectionTask = nil
    rediscoveryTask?.cancel()
    rediscoveryTask = nil
  }

  /// One timer serves the machine's `wakeUp`. It is only replaced when the deadline moved
  /// earlier; a timer that fires early finds nothing due and is re-armed.
  private func rearmTimer() {
    guard let deadline = machine.wakeUp else {
      timerGeneration += 1
      timerTask?.cancel()
      timerTask = nil
      timerDeadline = nil
      return
    }
    if timerTask != nil, let armed = timerDeadline, armed <= deadline { return }
    timerGeneration += 1
    timerTask?.cancel()
    timerDeadline = deadline
    let generation = timerGeneration
    let wait = max(deadline.timeIntervalSince(ports.clock.now()), 0)
    timerTask = Task {
      do { try await self.ports.clock.sleep(for: .seconds(wait)) } catch { return }
      self.timerFired(generation)
    }
  }

  private func timerFired(_ generation: Int) {
    guard generation == timerGeneration else { return }
    timerTask = nil
    timerDeadline = nil
    apply(.timerFired)
  }
}
