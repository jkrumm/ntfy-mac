import Foundation

/// What happened to a notification while its post was running.
enum InFlightFate {
  case keep
  /// A newer version of the notification is queued and will replace this one.
  case superseded
  /// The user or the server settled it; the notification must not stay on screen.
  case withdrawn
}

/// Turns stored messages into notifications and looks after them until the user is done.
///
/// - Posts go through a paced priority queue (`DeliveryQueue`) drained by one task that sleeps on
///   the injected `Clock`.
/// - A message counts as shown only when `poster.post` returned; then the history is told
///   (`markNotified`). One whose retries ran out stays unnotified, and `reconcile` picks it up
///   on the next boot. The queue itself is not persisted.
/// - After a post, an auto-dismiss timer and, for urgent messages, a re-alert timer run until
///   the user acknowledges, opens, or the server withdraws the message.
/// - Reminders that came due in the history are shown again, polled every
///   `reminderPollInterval` (the CLI writes snoozes into the history from another process, so no
///   in-process timer knows the next deadline).
///
/// The actor owns all mutable state. Every `await` that can interleave with a user response or a
/// server withdrawal re-checks what it assumed afterwards; see `InFlight`.
public actor DeliveryService: Delivering {
  /// How often the history is asked for due reminders.
  public static let reminderPollInterval: Duration = .seconds(30)
  /// `reconcile` resumes re-alerting only for messages younger than this (seconds); older ones
  /// stay unacknowledged in history but quiet.
  public static let reAlertResumeLimit: TimeInterval = 24 * 60 * 60
  /// Most rows `reconcile` looks at.
  static let reconcileLimit = 1000

  /// The message whose `poster.post` is running, which a withdrawal can overtake.
  struct InFlight {
    let ref: MessageRef
    let identifier: String
    var fate = InFlightFate.keep
  }

  let poster: any NotificationPoster
  let history: any HistoryStore
  let inbox: any HistoryInbox
  let configStore: any ConfigStore
  let clock: any Clock
  let log: @Sendable (String) -> Void

  var queue: DeliveryQueue
  var timers = DeliveryTimers()
  var inFlight: InFlight?
  var drainTask: Task<Void, Never>?
  var reminderTask: Task<Void, Never>?
  var isFiringReminders = false
  var stopped = false

  public init(
    poster: any NotificationPoster, history: any HistoryStore, inbox: any HistoryInbox,
    config: any ConfigStore, clock: any Clock, minimumInterval: TimeInterval = 1.5,
    log: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.poster = poster
    self.history = history
    self.inbox = inbox
    configStore = config
    self.clock = clock
    self.log = log
    queue = DeliveryQueue(minimumInterval: minimumInterval)
  }

  // MARK: Lifecycle

  /// Starts the reminder poll. Idempotent.
  public func start() {
    guard !stopped, reminderTask == nil else { return }
    reminderTask = Task { await self.pollReminders() }
  }

  /// Cancels every task the service owns and returns once none is left running. Queued
  /// notifications are dropped (`reconcile` finds them again on the next boot).
  public func shutdown() async {
    guard !stopped else { return }
    stopped = true
    queue.removeAll { _ in true }
    let tasks = [drainTask, reminderTask].compactMap { $0 } + timers.cancelAll()
    drainTask = nil
    reminderTask = nil
    for task in tasks { task.cancel() }
    for task in tasks { await task.value }
  }

  // MARK: Delivering

  public func deliver(_ message: NtfyMessage) {
    guard !stopped, !isPending(MessageRef(topic: message.topic, id: message.id)) else { return }
    dropSuperseded(by: message)
    queue.enqueue(.message(message, repeatsLeft: nil))
    startDraining()
  }

  public func announceMissed(_ messages: [NtfyMessage]) async {
    let fresh = messages.filter { !isPending(MessageRef(topic: $0.topic, id: $0.id)) }
    switch MissedMessagePolicy.decide(fresh, now: clock.now()) {
    case .individual(let toShow):
      for message in toShow { deliver(message) }
    case .summary(let count, let oldestTopic):
      let covers = fresh.map { MessageRef(topic: $0.topic, id: $0.id) }
      guard !stopped else { return }
      queue.enqueue(.summary(count: count, oldestTopic: oldestTopic, covers: covers))
      startDraining()
    case .silent:
      for message in fresh { await markNotified(MessageRef(topic: message.topic, id: message.id)) }
    }
  }

  // MARK: Shared helpers

  func isPending(_ ref: MessageRef) -> Bool {
    inFlight?.ref == ref || queue.contains { $0.ref == ref }
  }

  /// An update replaces the notification it updates: older queued items of the sequence go, a
  /// post in flight is not followed up, and the earlier notification's timers stop.
  private func dropSuperseded(by message: NtfyMessage) {
    let identifier = message.notificationIdentifier
    queue.removeAll { $0.identifier == identifier }
    if inFlight?.identifier == identifier, inFlight?.fate == .keep { inFlight?.fate = .superseded }
    timers.cancel(identifier: identifier)
  }

  func currentConfig() async -> Config {
    do throws(NtfyError) {
      return try await configStore.load()
    } catch {
      log("config not loaded, using defaults: \(error)")
      return Config()
    }
  }

  func markNotified(_ ref: MessageRef) async {
    do throws(NtfyError) {
      try await history.markNotified(topic: ref.topic, id: ref.id, at: clock.now())
    } catch {
      log("message \(ref.topic)/\(ref.id) not marked notified: \(error)")
    }
  }
}

extension Duration {
  var timeInterval: TimeInterval {
    let parts = components
    return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
  }
}
