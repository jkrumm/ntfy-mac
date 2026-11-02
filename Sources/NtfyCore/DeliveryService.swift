import Foundation

/// How `reconcile` announces the messages it finds unnotified.
enum Announcement {
  /// By the age of the oldest (`MissedMessagePolicy`).
  case byAge
  /// As one summary, whatever the age (the end of quiet hours with `digest`).
  case summary
  /// As one summary that says the messages came in during a meeting.
  case meetingSummary
  /// Each one through the queue, whatever the age (the end of quiet hours without `digest`).
  case each
}

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
/// - While `Config.pausedUntil` is in the future nothing is posted: messages stay unnotified in the
///   history, and the first moment the pause is over (its end, or the next reminder poll after
///   the config cleared it) `reconcile` shows them under `MissedMessagePolicy`.
/// - Quiet hours (`Config.quietHours`) hold messages back the same way, except priority 5 when the
///   urgent bypass is on. When the window ends, `reconcile` shows what was held: as one summary
///   with `digest`, else individually. A manual pause that outlasts the window wins; one
///   reconcile covers both.
/// - While a meeting is going on (`Config.meeting`: detected with `mode` `pause`, or the manual
///   override) messages are held back like quiet hours, priority 5 excepted with the urgent
///   bypass. The end of the meeting is not a time: the meeting source's change signal, the
///   override's end, or the reminder poll wakes the service, and `reconcile` shows what was
///   held as one summary that says it came in during a meeting. Local messages (`notify`)
///   are exempt, as with quiet hours.
/// - A topic that is muted, or a message below the topic's minimum priority, is stored and marked
///   notified without a notification, so a later reconcile never shows it.
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
  /// Decides what wall-clock time the quiet hours mean.
  let calendar: Calendar
  /// The detected meeting state; nil where the app has no detection (the CLI's one-shot uses).
  let meeting: (any MeetingStateProviding)?
  let log: @Sendable (String) -> Void

  var queue: DeliveryQueue
  var timers = DeliveryTimers()
  var inFlight: InFlight?
  var drainTask: Task<Void, Never>?
  var reminderTask: Task<Void, Never>?
  var meetingTask: Task<Void, Never>?
  var isFiringReminders = false
  /// Set when a post was held back by `Config.pausedUntil`; the resume reconciles once.
  var heldBack = false
  /// Set when quiet hours (not only a pause) held something back; the resume then digests.
  var quietHeld = false
  /// Set when a meeting held something back; the resume then summarises it as such.
  var meetingHeldBack = false
  /// Identifiers of `deliverLocal` messages, which topic settings, quiet hours
  /// and meetings do not apply to.
  /// Entries stay for the process lifetime: a handful of explicit `notify` calls.
  var localIdentifiers: Set<String> = []
  /// Auto-dismiss seconds for locally posted messages (`deliverLocal`), by notification
  /// identifier, consumed by the post.
  var dismissOverrides: [String: TimeInterval] = [:]
  var resumeTask: Task<Void, Never>?
  /// Reminders handed to the queue and not yet shown or given up on.
  var queuedReminders: Set<MessageRef> = []
  /// Reminders that were shown but could not be cleared in the history; never shown again.
  var unclearedReminders: Set<MessageRef> = []
  var stopped = false

  public init(
    poster: any NotificationPoster, history: any HistoryStore, inbox: any HistoryInbox,
    config: any ConfigStore, clock: any Clock, minimumInterval: TimeInterval = 1.5,
    calendar: Calendar = .current, meeting: (any MeetingStateProviding)? = nil,
    log: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.poster = poster
    self.history = history
    self.inbox = inbox
    configStore = config
    self.clock = clock
    self.calendar = calendar
    self.meeting = meeting
    self.log = log
    queue = DeliveryQueue(minimumInterval: minimumInterval)
  }

  // MARK: Lifecycle

  /// Starts the reminder poll and, with a meeting source, the watch for the end of a meeting.
  /// Idempotent.
  public func start() {
    guard !stopped, reminderTask == nil else { return }
    reminderTask = Task { await self.pollReminders() }
    guard let meeting else { return }
    meetingTask = Task {
      for await _ in meeting.changes() { await self.resumeIfPauseOver() }
    }
  }

  /// Cancels every task the service owns and returns once none is left running. Queued
  /// notifications are dropped (`reconcile` finds them again on the next boot).
  public func shutdown() async {
    guard !stopped else { return }
    stopped = true
    queue.removeAll { _ in true }
    let tasks =
      [drainTask, reminderTask, resumeTask, meetingTask].compactMap { $0 } + timers.cancelAll()
    drainTask = nil
    reminderTask = nil
    resumeTask = nil
    meetingTask = nil
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

  /// Queues a message that did not come from the server (the CLI's `notify`). `dismissAfter`
  /// replaces the configured auto-dismiss of its priority for this one notification; 0 means
  /// never.
  ///
  /// A local message is an explicit action of the user, so topic settings (mute, minimum
  /// priority), quiet hours and meetings do not apply to it. A manual pause still holds it back.
  public func deliverLocal(_ message: NtfyMessage, dismissAfter: TimeInterval?) {
    localIdentifiers.insert(message.notificationIdentifier)
    if let dismissAfter { dismissOverrides[message.notificationIdentifier] = dismissAfter }
    deliver(message)
  }

  public func announceMissed(_ messages: [NtfyMessage]) async {
    await announce(messages, as: .byAge)
  }

  /// Messages the topic settings suppress are marked notified and left out of every mode.
  func announce(_ messages: [NtfyMessage], as announcement: Announcement) async {
    let fresh = await settleSuppressed(messages)
    let decision =
      switch announcement {
      case .byAge: MissedMessagePolicy.decide(fresh, now: clock.now())
      case .summary, .meetingSummary: Self.digest(fresh)
      case .each: MissedMessageDecision.individual(fresh)
      }
    switch decision {
    case .individual(let toShow):
      for message in toShow { deliver(message) }
    case .summary(let count, let oldestTopic):
      let covers = fresh.map { MessageRef(topic: $0.topic, id: $0.id) }
      guard !stopped else { return }
      let cause: MissedSummaryCause = announcement == .meetingSummary ? .meeting : .away
      queue.enqueue(
        .summary(count: count, oldestTopic: oldestTopic, covers: covers, cause: cause))
      startDraining()
    case .silent:
      for message in fresh { await markNotified(MessageRef(topic: message.topic, id: message.id)) }
    }
  }

  // MARK: Shared helpers

  /// The messages that are not already pending; those the topic settings suppress are marked
  /// notified instead.
  private func settleSuppressed(_ messages: [NtfyMessage]) async -> [NtfyMessage] {
    let config = await currentConfig()
    var fresh: [NtfyMessage] = []
    for message in messages {
      let ref = MessageRef(topic: message.topic, id: message.id)
      guard !isPending(ref) else { continue }
      if config.suppresses(message) {
        await markNotified(ref)
      } else {
        fresh.append(message)
      }
    }
    return fresh
  }

  private static func digest(_ messages: [NtfyMessage]) -> MissedMessageDecision {
    guard let oldest = messages.min(by: { $0.time < $1.time }) else { return .silent }
    return .summary(count: messages.count, oldestTopic: oldest.topic)
  }

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
