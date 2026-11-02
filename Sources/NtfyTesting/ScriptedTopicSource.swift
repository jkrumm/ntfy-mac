import NtfyCore

/// Reports a fixed topic list, or fails every lookup.
public actor ScriptedTopicSource: TopicSource {
  public private(set) var callCount = 0
  private var topics: [String]
  private let failure: NtfyError?

  public init(topics: [String] = [], failingWith failure: NtfyError? = nil) {
    self.topics = topics
    self.failure = failure
  }

  public func subscribedTopics() throws(NtfyError) -> [String] {
    callCount += 1
    if let failure { throw failure }
    return topics
  }

  /// Changes what the following lookups report.
  public func setTopics(_ topics: [String]) {
    self.topics = topics
  }
}
