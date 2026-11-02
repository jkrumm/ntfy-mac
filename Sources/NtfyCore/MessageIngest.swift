import Foundation

/// Takes messages off the wire: store, then hand to delivery, then move the resume cursor.
///
/// History never loses a message: the cursor only moves past what is stored, and a failed store
/// is fetched again. A replay finds a stored message as a duplicate and does not deliver it
/// again; if the process died before it was shown, `DeliveryService.reconcile` picks it up from
/// the history's `unnotified` rows on the next boot.
public struct MessageIngest: Sendable {
  private let history: any HistoryStore
  private let delivery: any Delivering
  private let cursor: any CursorStore
  private let log: @Sendable (String) -> Void

  public init(
    history: any HistoryStore, delivery: any Delivering, cursor: any CursorStore,
    log: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.history = history
    self.delivery = delivery
    self.cursor = cursor
    self.log = log
  }

  /// A message from the live stream. A store failure is thrown and leaves the cursor where it
  /// was, so the next connection fetches the message again. A cursor failure is logged and
  /// ignored; delivery cannot fail from here.
  public func ingest(_ message: NtfyMessage) async throws(NtfyError) {
    if try await history.append(message) {
      await delivery.deliver(message)
    }
    await advanceCursor(to: message.id)
  }

  /// A batch fetched after an absence. Only messages not stored yet are announced; how (each,
  /// one summary, or not at all) is up to the delivery layer.
  /// - Returns: the id to resume from, or `nil` for an empty batch.
  public func ingestCatchUp(_ messages: [NtfyMessage]) async throws(NtfyError) -> String? {
    guard !messages.isEmpty else { return nil }
    var fresh: [NtfyMessage] = []
    var failure: NtfyError?
    for message in messages {
      do throws(NtfyError) {
        if try await history.append(message) { fresh.append(message) }
      } catch {
        failure = error
        break
      }
    }
    if !fresh.isEmpty { await delivery.announceMissed(fresh) }
    if let failure { throw failure }
    guard let newest = messages.reduce(nil as NtfyMessage?, { Self.newer($0, $1) }) else {
      return nil
    }
    await advanceCursor(to: newest.id)
    return newest.id
  }

  private static func newer(_ best: NtfyMessage?, _ next: NtfyMessage) -> NtfyMessage {
    guard let best else { return next }
    return next.time >= best.time ? next : best
  }

  private func advanceCursor(to id: String) async {
    do throws(NtfyError) {
      try await cursor.save(id)
    } catch {
      log("cursor not saved: \(error)")
    }
  }
}
