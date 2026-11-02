import NtfyCore

/// Records what would have been shown and keeps the delivered set a real centre would. Fails
/// every call, or a chosen number of the next ones.
public actor RecordingNotificationPoster: NotificationPoster {
  public struct MissedSummary: Sendable, Hashable {
    public let count: Int
    public let oldestTopic: String

    public init(count: Int, oldestTopic: String) {
      self.count = count
      self.oldestTopic = oldestTopic
    }
  }

  /// Every successful post, in order.
  public private(set) var posted: [NotificationContent] = []
  public private(set) var summaries: [MissedSummary] = []
  /// Every identifier passed to `remove`, in order, including unknown ones.
  public private(set) var removed: [String] = []
  /// What is currently shown: posts add, removals take away; `setDelivered` overrides it.
  public private(set) var delivered: Set<String> = []
  /// Calls to `post` and `postMissedSummary`, failed ones included.
  public private(set) var attempts = 0
  private let failure: NtfyError?
  private var failuresLeft = 0
  private var failureOfNext: NtfyError = .permissionDenied

  public init(failingWith failure: NtfyError? = nil) {
    self.failure = failure
  }

  /// Makes the next `count` calls to `post` or `postMissedSummary` throw `error`.
  public func failNext(_ count: Int, with error: NtfyError = .permissionDenied) {
    failuresLeft = count
    failureOfNext = error
  }

  public func setDelivered(_ identifiers: Set<String>) {
    delivered = identifiers
  }

  /// Identifiers of the posted contents, for compact assertions.
  public var postedIdentifiers: [String] { posted.map(\.identifier) }
  /// Message ids of the posted contents.
  public var postedIDs: [String] { posted.map(\.messageRef.id) }

  public func post(_ content: NotificationContent) throws(NtfyError) {
    try check()
    posted.append(content)
    delivered.insert(content.identifier)
  }

  public func postMissedSummary(count: Int, oldestTopic: String) throws(NtfyError) {
    try check()
    summaries.append(MissedSummary(count: count, oldestTopic: oldestTopic))
  }

  public func remove(identifiers: [String]) {
    removed.append(contentsOf: identifiers)
    delivered.subtract(identifiers)
  }

  public func deliveredIdentifiers() -> Set<String> { delivered }

  private func check() throws(NtfyError) {
    attempts += 1
    if let failure { throw failure }
    guard failuresLeft > 0 else { return }
    failuresLeft -= 1
    throw failureOfNext
  }
}
