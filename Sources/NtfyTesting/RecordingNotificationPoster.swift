import NtfyCore

/// Records what would have been shown; optionally fails every post.
public actor RecordingNotificationPoster: NotificationPoster {
  public private(set) var posted: [NtfyMessage] = []
  private let failure: NtfyError?

  public init(failingWith failure: NtfyError? = nil) {
    self.failure = failure
  }

  public func post(_ message: NtfyMessage) throws(NtfyError) {
    if let failure { throw failure }
    posted.append(message)
  }
}
