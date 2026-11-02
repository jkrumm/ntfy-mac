import ArgumentParser
import Foundation
import NtfyCore

/// The filters `ls`, `search` and `tail` share.
struct HistoryFilterOptions: ParsableArguments {
  static let defaultLimit = 20
  static let maxLimit = 1000

  @Option(name: .long, help: "Only this topic.") var topic: String?
  @Flag(name: .long, help: "Only unread messages.") var unread = false
  @Flag(name: .long, help: "Only messages that are not acknowledged.") var unacked = false
  @Option(name: .long, help: "Only messages with at least this priority (1-5).")
  var minPriority: Int?
  @Option(
    name: .long,
    help: "Only messages since a duration ago (30m, 2h, 1d) or an ISO 8601 time.")
  var since: String?
  @Option(name: .long, help: "At most this many messages (1-1000, default 20).")
  var limit: Int = Self.defaultLimit

  func validate() throws {
    if let topic, !TopicResolver.isValid(topic) {
      throw ValidationError("Invalid topic name \"\(topic)\": use 1-64 letters, digits, - or _.")
    }
    if let minPriority, !Priority.range.contains(minPriority) {
      throw ValidationError("--min-priority must be 1-5 (got \(minPriority)).")
    }
    if let since, TimePoint.parse(since, now: Date()) == nil {
      throw ValidationError(
        "--since must be a duration like 30m, 2h, 1d or an ISO 8601 time (got \(since)).")
    }
    guard (1...Self.maxLimit).contains(limit) else {
      throw ValidationError("--limit must be 1-\(Self.maxLimit) (got \(limit)).")
    }
  }

  func query(text: String? = nil, now: Date) -> HistoryQuery {
    HistoryQuery(
      topic: topic, unreadOnly: unread, text: text,
      minPriority: minPriority.flatMap(Priority.init(rawValue:)),
      since: since.flatMap { TimePoint.parse($0, now: now) }, limit: limit)
  }

  /// Newest first. `--unacked` is not a store filter, so it is applied page by page.
  func fetch(
    _ inbox: any HistoryInbox, text: String? = nil, now: Date
  ) async throws(NtfyError) -> [StoredMessage] {
    var query = query(text: text, now: now)
    guard unacked else { return try await inbox.entries(query) }
    let wanted = query.limit
    query.limit = 200
    var result: [StoredMessage] = []
    while result.count < wanted {
      let page = try await inbox.entries(query)
      result += page.filter { !$0.isAcknowledged }
      if page.count < query.limit { break }
      query.offset += query.limit
    }
    return Array(result.prefix(wanted))
  }
}
