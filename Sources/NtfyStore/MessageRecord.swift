import Foundation
import GRDB
import NtfyCore

/// One row of the `message` table.
struct MessageRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
  static let databaseTableName = "message"

  var server: String
  var topic: String
  var id: String
  var sequenceID: String
  var time: Date
  var title: String?
  var body: String
  var priority: Int
  var tags: String
  var payload: Data
  var readAt: Date?
  var ackedAt: Date?
  var notifiedAt: Date?
  var remindAt: Date?
  var withdrawnAt: Date?
  var createdAt: Date

  enum CodingKeys: String, CodingKey {
    case server, topic, id, time, title, body, priority, tags, payload
    case sequenceID = "sequence_id"
    case readAt = "read_at"
    case ackedAt = "acked_at"
    case notifiedAt = "notified_at"
    case remindAt = "remind_at"
    case withdrawnAt = "withdrawn_at"
    case createdAt = "created_at"
  }

  init(_ message: NtfyMessage, server: String, createdAt: Date) throws {
    self.server = server
    topic = message.topic
    id = message.id
    sequenceID = message.sequenceID ?? message.id
    time = message.time
    title = message.title
    body = message.body
    priority = message.priority.rawValue
    tags = String(bytes: try Self.encoder.encode(message.tags), encoding: .utf8) ?? "[]"
    payload = try Self.encoder.encode(message)
    self.createdAt = createdAt
  }

  func message() throws -> NtfyMessage {
    try Self.decoder.decode(NtfyMessage.self, from: payload)
  }

  func stored() throws -> StoredMessage {
    StoredMessage(
      message: try message(), readAt: readAt, ackedAt: ackedAt, notifiedAt: notifiedAt,
      remindAt: remindAt)
  }

  private static let encoder = JSONEncoder()
  private static let decoder = JSONDecoder()
}
