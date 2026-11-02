import Foundation
import NtfyCore

/// The history-and-delivery pair the socket acts on: the same store and the one
/// `DeliveryService` that owns its notifications. It is the same for a configured server and for
/// the local pipeline (no server), so a local message behaves the same either way.
public struct LocalMessaging: Sendable {
  private let history: any HistoryStore & HistoryInbox
  private let delivery: DeliveryService

  public init(history: any HistoryStore & HistoryInbox, delivery: DeliveryService) {
    self.history = history
    self.delivery = delivery
  }

  /// Stores the message and hands it to delivery, which paces it, honours a pause and retries.
  public func post(_ message: NtfyMessage, dismissAfter: TimeInterval?) async throws(NtfyError) {
    try await history.append(message)
    await delivery.deliverLocal(message, dismissAfter: dismissAfter)
  }

  /// False when the history does not know the message.
  public func acknowledge(topic: String, id: String) async throws(NtfyError) -> Bool {
    guard try await history.message(topic: topic, id: id) != nil else { return false }
    await delivery.acknowledge(topic: topic, id: id)
    return true
  }

  /// Acknowledges every unacknowledged message (of one topic, if given) and returns how many.
  public func acknowledgeAll(topic: String?) async throws(NtfyError) -> Int {
    let pending = try await history.unacknowledged(minPriority: .min)
      .filter { topic == nil || $0.message.topic == topic }
    for entry in pending {
      await delivery.acknowledge(topic: entry.message.topic, id: entry.message.id)
    }
    return pending.count
  }

  /// False when the history does not know the message. It is shown again by the reminder poll.
  public func remind(topic: String, id: String, until: Date) async throws(NtfyError) -> Bool {
    guard try await history.message(topic: topic, id: id) != nil else { return false }
    try await history.snooze(topic: topic, id: id, until: until)
    return true
  }
}

/// What a running pipeline offers the socket handler.
public struct PipelineHandles: Sendable {
  public let messages: LocalMessaging
  /// Nil in the local pipeline, which has no stream.
  public let supervisor: StreamSupervisor?

  public init(messages: LocalMessaging, supervisor: StreamSupervisor?) {
    self.messages = messages
    self.supervisor = supervisor
  }
}
