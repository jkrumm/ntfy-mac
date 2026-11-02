import Foundation
import NtfyCore

/// Watches the history for rows that appear after it started, by polling the read-only database.
///
/// Rows are told apart by topic and id. Each poll asks for the rows newer than the newest one seen
/// minus a window (a row can be stored a little after its server timestamp), so only the ids
/// inside that window are remembered and memory stays bounded. A row whose timestamp is older
/// than the window when it is stored (a catch-up after a long outage) is not reported. A poll
/// reads pages until a short one comes back, so a burst larger than a page loses nothing.
actor HistoryFollower {
  static let window: TimeInterval = 60
  static let pageSize = 500
  /// Pages one poll reads at most, so a huge backlog cannot hold a poll forever.
  static let maxPages = 20
  static let defaultInterval = Duration.milliseconds(500)

  private struct Key: Hashable {
    let topic: String
    let id: String
  }

  private let feed: HistoryFeed
  private let filter: HistoryQuery
  private let clock: any NtfyCore.Clock
  private let interval: Duration
  private var seen: [Key: Date] = [:]
  private var watermark: Date

  /// - Parameters:
  ///   - filter: Topic and minimum priority; the other fields are ignored.
  ///   - seed: Rows already shown; they never count as new.
  ///   - start: Rows older than `start` minus the window are out of reach.
  init(
    feed: HistoryFeed, filter: HistoryQuery, clock: any NtfyCore.Clock, start: Date,
    seed: [StoredMessage] = [], interval: Duration = HistoryFollower.defaultInterval
  ) {
    self.feed = feed
    self.filter = filter
    self.clock = clock
    self.interval = interval
    watermark = start
    for entry in seed {
      seen[Key(topic: entry.message.topic, id: entry.message.id)] = entry.message.time
      watermark = max(watermark, entry.message.time)
    }
  }

  /// How many ids are remembered; bounded by the window.
  var seenCount: Int { seen.count }

  /// Rows not seen before, oldest first.
  func poll() async throws(NtfyError) -> [StoredMessage] {
    guard let inbox = try await feed.inbox() else { return [] }
    let since = watermark.addingTimeInterval(-Self.window)
    var found: [StoredMessage] = []
    for page in 0..<Self.maxPages {
      let query = HistoryQuery(
        topic: filter.topic, minPriority: filter.minPriority, since: since,
        limit: Self.pageSize, offset: page * Self.pageSize)
      let rows = try await inbox.entries(query)
      found += rows
      if rows.count < Self.pageSize { break }
    }
    var fresh: [StoredMessage] = []
    for entry in found.reversed() {
      let key = Key(topic: entry.message.topic, id: entry.message.id)
      guard seen[key] == nil else { continue }
      seen[key] = entry.message.time
      watermark = max(watermark, entry.message.time)
      fresh.append(entry)
    }
    let floor = watermark.addingTimeInterval(-Self.window)
    seen = seen.filter { $0.value >= floor }
    return fresh
  }

  /// Hands every new row to `handle` until cancelled.
  func follow(_ handle: @Sendable (StoredMessage) async throws -> Void) async throws {
    _ = try await loop(until: nil) { entry in
      try await handle(entry)
      return false
    }
  }

  /// The first new row `predicate` accepts, or nil once `deadline` has passed.
  func firstMatch(
    until deadline: Date, where predicate: @Sendable (StoredMessage) -> Bool
  ) async throws -> StoredMessage? {
    var found: StoredMessage?
    _ = try await loop(until: deadline) { entry in
      guard predicate(entry) else { return false }
      found = entry
      return true
    }
    return found
  }

  /// Polls, sleeps, repeats. `visit` returns true to stop; the result says whether it did.
  private func loop(
    until deadline: Date?, _ visit: (StoredMessage) async throws -> Bool
  ) async throws -> Bool {
    while true {
      for entry in try await poll() {
        guard try await !visit(entry) else { return true }
      }
      var nap = interval
      if let deadline {
        let remaining = deadline.timeIntervalSince(clock.now())
        guard remaining > 0 else { return false }
        nap = min(interval, .seconds(remaining))
      }
      try await clock.sleep(for: nap)
    }
  }
}
