import Foundation

/// Time source. Production uses the system clock; tests advance a fake by hand.
public protocol Clock: Sendable {
  func now() -> Date
  func sleep(for duration: Duration) async throws
}

/// A live subscription to ntfy topics.
public protocol MessageStream: Sendable {
  /// Yields every event of one connection. The contract for the consumer:
  /// - A normal finish means the server closed the connection cleanly; reconnect with `since`.
  /// - A failure finishes the stream with an `NtfyError` (`AsyncThrowingStream` cannot carry a
  ///   typed failure in the current stdlib).
  /// - A consumer stops the subscription by cancelling its own task; that never yields an error.
  func events(topics: [String], since: String?) -> AsyncThrowingStream<StreamEvent, any Error>
}

/// One-shot catch-up: the messages a topic cached after the given id.
public protocol MessagePoller: Sendable {
  func poll(topics: [String], since: String?) async throws(NtfyError) -> [NtfyMessage]
}

/// The topics the account is subscribed to on the server.
public protocol TopicSource: Sendable {
  func subscribedTopics() async throws(NtfyError) -> [String]
}

/// Id of the last message that was fully processed, the resume point after a restart.
public protocol CursorStore: Sendable {
  func load() async throws(NtfyError) -> String?
  func save(_ id: String) async throws(NtfyError)
}

/// Something that happened to the machine, independent of the server.
public enum SystemEvent: Sendable, Hashable {
  case didWake
  case willSleep
  case pathChanged(online: Bool)
}

/// Power and network changes of the host.
public protocol SystemEvents: Sendable {
  func events() -> AsyncStream<SystemEvent>
}

/// Where the access token is kept (the Keychain in production).
public protocol SecretStore: Sendable {
  func token() async throws(NtfyError) -> String?
  func setToken(_ token: String) async throws(NtfyError)
  func deleteToken() async throws(NtfyError)
}

/// Why a summary notification stands in for messages.
public enum MissedSummaryCause: Sendable, Hashable {
  /// They arrived while the app was away, or during quiet hours.
  case away
  /// They arrived while a video meeting was going on.
  case meeting
}

/// Shows notifications and withdraws them again.
public protocol NotificationPoster: Sendable {
  /// Shows `content`. A notification already delivered under the same `identifier` is replaced:
  /// the adapter removes it, then adds the new one, so an update (or a re-alert) makes noise again.
  func post(_ content: NotificationContent) async throws(NtfyError)
  /// One notification standing in for `count` messages that were held back or missed.
  func postMissedSummary(count: Int, oldestTopic: String, cause: MissedSummaryCause)
    async throws(NtfyError)
  /// Withdraws delivered notifications. Unknown identifiers are ignored.
  func remove(identifiers: [String]) async
  /// The identifiers of the notifications currently shown.
  func deliveredIdentifiers() async -> Set<String>
}

extension NotificationPoster {
  /// A summary of messages missed while away.
  public func postMissedSummary(count: Int, oldestTopic: String) async throws(NtfyError) {
    try await postMissedSummary(count: count, oldestTopic: oldestTopic, cause: .away)
  }
}

/// Persistent message history as the ingest and delivery layers use it.
///
/// A message with the same `sequenceID` (falling back to `id`) as an earlier one in its topic
/// supersedes it: queries return only the newest, non-withdrawn row of each sequence.
public protocol HistoryStore: Sendable {
  /// Returns `true` if the message was new; the dedup key is topic + id.
  @discardableResult
  func append(_ message: NtfyMessage) async throws(NtfyError) -> Bool
  /// Newest first.
  func recent(limit: Int) async throws(NtfyError) -> [NtfyMessage]
  /// Id of the newest stored message, used as the stream resume cursor.
  func lastMessageID() async throws(NtfyError) -> String?

  /// Records that the message was shown.
  func markNotified(topic: String, id: String, at time: Date) async throws(NtfyError)
  /// Stored messages that were never shown, oldest first (boot reconcile).
  func unnotified(limit: Int, offset: Int) async throws(NtfyError) -> [NtfyMessage]

  /// The server deleted the sequence (`message_delete`): hide every row of it.
  func withdraw(topic: String, sequenceID: String) async throws(NtfyError)
  /// The server cleared the sequence (`message_clear`): mark it read and acknowledged.
  func markCleared(topic: String, sequenceID: String) async throws(NtfyError)

  /// Drops rows beyond the policy and returns how many went.
  @discardableResult
  func prune(policy: RetentionPolicy, now: Date) async throws(NtfyError) -> Int
}

/// What the user does with stored messages: browse, read, acknowledge, snooze.
public protocol HistoryInbox: Sendable {
  /// Newest first.
  func entries(_ query: HistoryQuery) async throws(NtfyError) -> [StoredMessage]

  /// One visible message by its key, nil when unknown or withdrawn. Callbacks from outside the
  /// process (a notification click) go through this, never through ids they carry.
  func message(topic: String, id: String) async throws(NtfyError) -> StoredMessage?

  /// How many messages match, ignoring `limit` and `offset` (the total behind a paged `entries`).
  func count(_ query: HistoryQuery) async throws(NtfyError) -> Int
  /// Every topic with visible messages, newest message first (ties by name).
  func topics() async throws(NtfyError) -> [TopicSummary]

  func markRead(topic: String, id: String) async throws(NtfyError)
  /// Makes a read message unread again; acknowledgement stays.
  func markUnread(topic: String, id: String) async throws(NtfyError)
  func markAllRead(topic: String) async throws(NtfyError)
  /// Acknowledging also marks the message read and drops its reminder.
  func acknowledge(topic: String, id: String) async throws(NtfyError)
  /// Not yet acknowledged and at least `minPriority`, oldest first.
  func unacknowledged(minPriority: Priority) async throws(NtfyError) -> [StoredMessage]

  func snooze(topic: String, id: String, until: Date) async throws(NtfyError)
  func clearReminder(topic: String, id: String) async throws(NtfyError)
  /// Snoozed messages whose time has come, earliest first.
  func dueReminders(now: Date) async throws(NtfyError) -> [StoredMessage]
}

/// Tells an in-process observer that the history changed.
public protocol HistoryObserving: Sendable {
  /// One element after a committed write (append, read, acknowledge, snooze, withdraw, clear,
  /// prune), starting from the subscription: no replay. Bursts coalesce: a consumer that has not
  /// caught up sees one element for any number of writes. Only writes made through this object
  /// are signalled; another process's writes (there are none today: the CLI goes through the
  /// app) are not.
  func changes() -> AsyncStream<Void>
}

/// User-editable settings.
public protocol ConfigStore: Sendable {
  func load() async throws(NtfyError) -> Config
  /// Like `load`, but a file that exists and is unreadable or malformed is an error rather than an
  /// empty config. For callers that act on "nothing configured" (`doctor`, `setup`).
  func loadChecked() async throws(NtfyError) -> Config
  func save(_ config: Config) async throws(NtfyError)
  /// Read-modify-write as one step, so a concurrent writer's change is not reverted by a stale
  /// snapshot. Prefer this to `load` + `save` for anything but a full replace.
  func update(_ change: @Sendable (inout Config) -> Void) async throws(NtfyError)
}

extension ConfigStore {
  /// Stores that cannot hold a malformed file (in-memory fakes) just load.
  public func loadChecked() async throws(NtfyError) -> Config {
    try await load()
  }
}
