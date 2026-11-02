import Foundation
import NtfyCore

/// What the socket handler may ask of a running pipeline.
extension AppPipeline {
  func connectionStatus() async -> ConnectionStatus {
    await supervisor.currentStatus
  }

  func reconnect() async {
    await supervisor.restart()
  }

  /// Stores the message in the history and hands it to delivery, which paces it, honours a
  /// pause and retries.
  func postLocal(_ message: NtfyMessage, dismissAfter: TimeInterval?) async throws(NtfyError) {
    try await store.append(message)
    await delivery.deliverLocal(message, dismissAfter: dismissAfter)
  }

  /// False when the history does not know the message.
  func acknowledge(topic: String, id: String) async throws(NtfyError) -> Bool {
    guard try await store.message(topic: topic, id: id) != nil else { return false }
    await delivery.acknowledge(topic: topic, id: id)
    return true
  }

  /// False when the history does not know the message. It is shown again by the reminder poll.
  func remind(topic: String, id: String, until: Date) async throws(NtfyError) -> Bool {
    guard try await store.message(topic: topic, id: id) != nil else { return false }
    try await store.snooze(topic: topic, id: id, until: until)
    return true
  }
}
