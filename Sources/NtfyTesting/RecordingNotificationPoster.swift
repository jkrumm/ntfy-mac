import NtfyCore

/// Records what would have been shown; optionally fails every post.
public actor RecordingNotificationPoster: NotificationPoster {
  public struct MissedSummary: Sendable, Hashable {
    public let count: Int
    public let oldestTopic: String

    public init(count: Int, oldestTopic: String) {
      self.count = count
      self.oldestTopic = oldestTopic
    }
  }

  public private(set) var posted: [NtfyMessage] = []
  public private(set) var summaries: [MissedSummary] = []
  private let failure: NtfyError?

  public init(failingWith failure: NtfyError? = nil) {
    self.failure = failure
  }

  public func post(_ message: NtfyMessage) throws(NtfyError) {
    if let failure { throw failure }
    posted.append(message)
  }

  public func postMissedSummary(count: Int, oldestTopic: String) throws(NtfyError) {
    if let failure { throw failure }
    summaries.append(MissedSummary(count: count, oldestTopic: oldestTopic))
  }
}
