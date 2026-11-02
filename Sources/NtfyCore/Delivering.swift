/// What ingest needs from the delivery layer: hand over messages, and pass on what the server
/// withdrew. Nothing here throws; a notification that cannot be shown is the delivery layer's
/// problem (retry, then reconcile on the next boot), never the stream's.
public protocol Delivering: Sendable {
  /// Queues a new message for notification.
  func deliver(_ message: NtfyMessage) async
  /// Messages that arrived while the app was away, announced as `MissedMessagePolicy` decides:
  /// each one, one summary, or none.
  func announceMissed(_ messages: [NtfyMessage]) async
  /// The server deleted the sequence (`message_delete`).
  func withdraw(topic: String, sequenceID: String) async
  /// The server cleared the sequence (`message_clear`).
  func clear(topic: String, sequenceID: String) async
}

extension Delivering {
  /// A `StreamSupervisor.Options.sink` that forwards `message_delete` and `message_clear`.
  public func eventSink() -> StreamEventSink {
    { event in
      switch event {
      case .messageDelete(let topic, let sequenceID):
        await self.withdraw(topic: topic, sequenceID: sequenceID)
      case .messageClear(let topic, let sequenceID):
        await self.clear(topic: topic, sequenceID: sequenceID)
      case .open, .keepalive, .pollRequest, .message:
        break
      }
    }
  }
}
