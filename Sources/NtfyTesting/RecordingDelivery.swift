import NtfyCore

/// Records what the ingest and stream layers hand to delivery, without showing anything.
public actor RecordingDelivery: Delivering {
  public struct Sequence: Sendable, Hashable {
    public let topic: String
    public let sequenceID: String

    public init(topic: String, sequenceID: String) {
      self.topic = topic
      self.sequenceID = sequenceID
    }
  }

  public private(set) var delivered: [NtfyMessage] = []
  /// One entry per `announceMissed` call.
  public private(set) var announced: [[NtfyMessage]] = []
  public private(set) var withdrawn: [Sequence] = []
  public private(set) var cleared: [Sequence] = []

  public init() {}

  public func deliver(_ message: NtfyMessage) {
    delivered.append(message)
  }

  public func announceMissed(_ messages: [NtfyMessage]) {
    announced.append(messages)
  }

  public func withdraw(topic: String, sequenceID: String) {
    withdrawn.append(Sequence(topic: topic, sequenceID: sequenceID))
  }

  public func clear(topic: String, sequenceID: String) {
    cleared.append(Sequence(topic: topic, sequenceID: sequenceID))
  }
}
