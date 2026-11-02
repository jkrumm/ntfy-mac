import Foundation
import NtfyCore
import NtfyIPC

struct TopicStats: Encodable, Equatable {
  let topic: String
  let total: Int
  let unread: Int
  let unacknowledged: Int
}

struct HistoryStats: Encodable, Equatable {
  let total: Int
  let unread: Int
  let unacknowledged: Int
  let lastMessageAt: Date?
  let topics: [TopicStats]

  private enum CodingKeys: String, CodingKey {
    case total, unread, unacknowledged, lastMessageAt, topics
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(total, forKey: .total)
    try container.encode(unread, forKey: .unread)
    try container.encode(unacknowledged, forKey: .unacknowledged)
    try container.encode(lastMessageAt, forKey: .lastMessageAt)
    try container.encode(topics, forKey: .topics)
  }

  static let empty = HistoryStats(
    total: 0, unread: 0, unacknowledged: 0, lastMessageAt: nil, topics: [])

  /// Counts over `entries` (newest first).
  init(_ entries: [StoredMessage]) {
    total = entries.count
    unread = entries.filter { !$0.isRead }.count
    unacknowledged = entries.filter { !$0.isAcknowledged }.count
    lastMessageAt = entries.first?.message.time
    topics = Dictionary(grouping: entries, by: \.message.topic).map { topic, group in
      TopicStats(
        topic: topic, total: group.count, unread: group.filter { !$0.isRead }.count,
        unacknowledged: group.filter { !$0.isAcknowledged }.count)
    }.sorted { $0.topic < $1.topic }
  }

  private init(
    total: Int, unread: Int, unacknowledged: Int, lastMessageAt: Date?, topics: [TopicStats]
  ) {
    self.total = total
    self.unread = unread
    self.unacknowledged = unacknowledged
    self.lastMessageAt = lastMessageAt
    self.topics = topics
  }
}

/// What `status --json` prints. Every key is always present; unknown values are `null`.
struct StatusReport: Encodable {
  var running: Bool
  var version = Version.current
  var appVersion: String?
  var connection: String?
  var configured: Bool
  var server: String?
  /// Known from files: local additions, `NTFY_TOPICS` and the history; not the live server list.
  var topics: [String]
  var paused: Bool
  var pausedUntil: Date?
  var permission: PermissionSummary?
  var history: HistoryStats

  private enum CodingKeys: String, CodingKey {
    case running, version, appVersion, connection, configured, server, topics, paused
    case pausedUntil, permission, history
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(running, forKey: .running)
    try container.encode(version, forKey: .version)
    try container.encode(appVersion, forKey: .appVersion)
    try container.encode(connection, forKey: .connection)
    try container.encode(configured, forKey: .configured)
    try container.encode(server, forKey: .server)
    try container.encode(topics, forKey: .topics)
    try container.encode(paused, forKey: .paused)
    try container.encode(pausedUntil, forKey: .pausedUntil)
    try container.encode(permission, forKey: .permission)
    try container.encode(history, forKey: .history)
  }

  func text() -> String {
    var lines = ["ntfy-mac status (\(version))", ""]
    if running {
      lines.append("  App:         running (\(appVersion ?? "?"), \(connection ?? "unknown"))")
    } else {
      lines.append("  App:         not running (start it with: ntfy-mac start)")
    }
    lines.append("  Server:      \(server ?? "not configured (run: ntfy-mac setup)")")
    lines.append("  Paused:      \(pauseText)")
    lines.append("  Permissions: \(permissionText)")
    lines.append("  History:     \(historyText)")
    lines.append(
      "  Topics:      \(topics.isEmpty ? "(none known)" : topics.joined(separator: ", "))")
    return lines.joined(separator: "\n")
  }

  private var pauseText: String {
    guard let pausedUntil, paused else { return "no" }
    return PauseWindow.isIndefinite(pausedUntil)
      ? "yes, until resume" : "until \(MessageText.timestamp(pausedUntil))"
  }

  private var permissionText: String {
    guard let permission else { return "unknown (app not running)" }
    guard !permission.problems.isEmpty else { return permission.usable ? "ok" : "not usable" }
    let codes = permission.problems.map(\.code).joined(separator: ", ")
    return (permission.usable ? "allowed, with caveats: " : "not usable: ") + codes
  }

  private var historyText: String {
    var text = "\(history.total) message(s), \(history.unread) unread, "
    text += "\(history.unacknowledged) unacknowledged"
    if let last = history.lastMessageAt { text += ", last \(MessageText.timestamp(last))" }
    return text
  }
}
