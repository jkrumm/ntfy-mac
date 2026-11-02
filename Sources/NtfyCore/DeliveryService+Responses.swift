import Foundation

/// What the user and the server do to notifications that are queued or shown.
extension DeliveryService {
  /// The user acknowledged the message: its re-alerts and dismissal stop and it is withdrawn.
  public func acknowledge(topic: String, id: String) async {
    let ref = MessageRef(topic: topic, id: id)
    let identifier = await identifier(for: ref)
    forget(ref: ref, identifier: identifier)
    await recording("acknowledge \(topic)/\(id)") { () async throws(NtfyError) in
      try await inbox.acknowledge(topic: topic, id: id)
    }
    await poster.remove(identifiers: [identifier])
  }

  /// The user clicked the notification body: the same as `acknowledge`, which also marks the
  /// message read, so re-alerts stop.
  public func opened(topic: String, id: String) async {
    await acknowledge(topic: topic, id: id)
  }

  /// The server deleted the sequence (`message_delete`).
  public func withdraw(topic: String, sequenceID: String) async {
    let identifier = "\(topic)/\(sequenceID)"
    forget(identifier: identifier)
    await recording("withdraw \(identifier)") { () async throws(NtfyError) in
      try await history.withdraw(topic: topic, sequenceID: sequenceID)
    }
    await poster.remove(identifiers: [identifier])
  }

  /// The server cleared the sequence (`message_clear`).
  public func clear(topic: String, sequenceID: String) async {
    let identifier = "\(topic)/\(sequenceID)"
    forget(identifier: identifier)
    await recording("clear \(identifier)") { () async throws(NtfyError) in
      try await history.markCleared(topic: topic, sequenceID: sequenceID)
    }
    await poster.remove(identifiers: [identifier])
  }

  // MARK: Helpers

  /// Drops everything pending for one message: queued posts, timers, a post in flight.
  private func forget(ref: MessageRef, identifier: String) {
    queue.removeAll { $0.ref == ref }
    timers.cancel(ref: ref)
    if inFlight?.ref == ref { inFlight?.fate = .withdrawn }
  }

  /// Drops everything pending for one notification, whichever message of it.
  private func forget(identifier: String) {
    queue.removeAll { $0.identifier == identifier }
    timers.cancel(identifier: identifier)
    if inFlight?.identifier == identifier { inFlight?.fate = .withdrawn }
  }

  /// The notification a message is shown under: from a running timer, else from the history
  /// (the sequence id is not part of the callback), else the message id itself.
  private func identifier(for ref: MessageRef) async -> String {
    if let identifier = timers.identifier(for: ref) { return identifier }
    let query = HistoryQuery(topic: ref.topic, limit: Self.reconcileLimit)
    let stored = (try? await inbox.entries(query))?.first { $0.message.id == ref.id }
    return stored?.message.notificationIdentifier ?? "\(ref.topic)/\(ref.id)"
  }

  private func recording(
    _ what: String, _ work: () async throws(NtfyError) -> Void
  ) async {
    do throws(NtfyError) {
      try await work()
    } catch {
      log("\(what) not recorded: \(error)")
    }
  }
}
