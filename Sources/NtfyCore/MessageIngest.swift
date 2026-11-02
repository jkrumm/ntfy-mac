import Foundation

/// Takes messages off the wire: store, then notify, then move the resume cursor.
///
/// History never loses a message: the cursor only moves past what is stored, and a failed store
/// is fetched again. A notification is at-most-once: if the process dies between the store and
/// the post, the replay finds the message already stored, counts it as a duplicate and does not
/// notify. Wave 3 reconciles delivery.
public struct MessageIngest: Sendable {
  private let history: any HistoryStore
  private let poster: any NotificationPoster
  private let cursor: any CursorStore
  private let clock: any Clock
  private let log: @Sendable (String) -> Void

  public init(
    history: any HistoryStore, poster: any NotificationPoster, cursor: any CursorStore,
    clock: any Clock, log: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.history = history
    self.poster = poster
    self.cursor = cursor
    self.clock = clock
    self.log = log
  }

  /// A message from the live stream. A store failure is thrown and leaves the cursor where it
  /// was, so the next connection fetches the message again. A notification or cursor failure is
  /// logged and ignored.
  public func ingest(_ message: NtfyMessage) async throws(NtfyError) {
    if try await history.append(message) {
      await post(message)
    }
    await advanceCursor(to: message.id)
  }

  /// A batch fetched after an absence. Only messages not stored yet are announced, and how
  /// (each, one summary, or not at all) follows `MissedMessagePolicy`.
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
    await announce(fresh)
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

  private func announce(_ fresh: [NtfyMessage]) async {
    switch MissedMessagePolicy.decide(fresh, now: clock.now()) {
    case .silent:
      return
    case .summary(let count, let oldestTopic):
      do throws(NtfyError) {
        try await poster.postMissedSummary(count: count, oldestTopic: oldestTopic)
      } catch {
        log("missed-message summary not posted: \(error)")
      }
    case .individual(let messages):
      for message in messages { await post(message) }
    }
  }

  private func post(_ message: NtfyMessage) async {
    do throws(NtfyError) {
      try await poster.post(message)
    } catch {
      log("notification not posted: \(error)")
    }
  }

  private func advanceCursor(to id: String) async {
    do throws(NtfyError) {
      try await cursor.save(id)
    } catch {
      log("cursor not saved: \(error)")
    }
  }
}
