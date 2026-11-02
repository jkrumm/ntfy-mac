import Foundation
import NtfyCore

public enum ExportFormat: String, Sendable, CaseIterable, Hashable {
  case json
  case csv

  public var fileExtension: String { rawValue }

  public var mimeType: String { self == .json ? "application/json" : "text/csv" }
}

/// An export ready to be written to the file the user picked.
public struct HistoryExport: Sendable, Hashable {
  public let data: Data
  public let suggestedFileName: String
  public let format: ExportFormat
}

/// Turns messages into a JSON or CSV file. Pure: no I/O, the same input always gives the same
/// bytes.
///
/// The JSON fields are the ones `ntfy-mac ls --json` prints, so a script can read either.
public enum HistoryExporter {
  public static let csvHeader = [
    "topic", "id", "time", "title", "message", "priority", "tags", "read", "acknowledged", "click",
    "attachment",
  ]

  /// `scope` is the topic the messages belong to, nil for all of them; it names the file.
  public static func export(
    _ messages: [StoredMessage], as format: ExportFormat, scope: String?, now: Date
  ) -> HistoryExport {
    let data = format == .json ? json(messages) : csv(messages)
    let stamp = now.formatted(Date.ISO8601FormatStyle()).filter { $0 != "-" && $0 != ":" }
    return HistoryExport(
      data: data, suggestedFileName: "ntfy-\(scope ?? "all")-\(stamp).\(format.fileExtension)",
      format: format)
  }

  /// An array of objects with sorted keys and ISO 8601 times; absent values are `null`.
  public static func json(_ messages: [StoredMessage]) -> Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return (try? encoder.encode(messages.map(ExportedMessage.init))) ?? Data("[]".utf8)
  }

  /// RFC 4180: a header row, CRLF after every record, fields with a comma, quote or line break
  /// quoted. A text cell that a spreadsheet would run as a formula gets a leading `'`.
  public static func csv(_ messages: [StoredMessage]) -> Data {
    var lines = [csvHeader.joined(separator: ",")]
    for stored in messages {
      let message = stored.message
      let cells = [
        defused(message.topic), defused(message.id), message.time.formatted(.iso8601),
        defused(message.title ?? ""), defused(message.body), String(message.priority.rawValue),
        defused(message.tags.joined(separator: " ")), String(stored.isRead),
        String(stored.isAcknowledged), defused(message.click?.absoluteString ?? ""),
        defused(message.attachment?.url.absoluteString ?? ""),
      ]
      lines.append(cells.map(quoted).joined(separator: ","))
    }
    return Data((lines.joined(separator: "\r\n") + "\r\n").utf8)
  }

  private static let formulaStarts: Set<Character> = ["=", "+", "-", "@", "\t", "\r"]

  static func defused(_ cell: String) -> String {
    guard let first = cell.first, formulaStarts.contains(first) else { return cell }
    return "'" + cell
  }

  private static func quoted(_ cell: String) -> String {
    guard cell.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return cell }
    return "\"" + cell.replacingOccurrences(of: "\"", with: "\"\"") + "\""
  }
}

private struct ExportedMessage: Encodable {
  let stored: StoredMessage

  init(_ stored: StoredMessage) { self.stored = stored }

  private enum CodingKeys: String, CodingKey {
    case topic, id, time, title, message, priority, tags, read, acknowledged, click, attachments
  }

  func encode(to encoder: any Encoder) throws {
    let message = stored.message
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(message.topic, forKey: .topic)
    try container.encode(message.id, forKey: .id)
    try container.encode(message.time, forKey: .time)
    try container.encode(message.title, forKey: .title)
    try container.encode(message.body, forKey: .message)
    try container.encode(message.priority.rawValue, forKey: .priority)
    try container.encode(message.tags, forKey: .tags)
    try container.encode(stored.isRead, forKey: .read)
    try container.encode(stored.isAcknowledged, forKey: .acknowledged)
    try container.encode(message.click?.absoluteString, forKey: .click)
    let attachments = message.attachment.map {
      [
        ExportedAttachment(
          name: $0.name, url: $0.url.absoluteString, type: $0.mimeType, size: $0.size)
      ]
    }
    try container.encode(attachments ?? [], forKey: .attachments)
  }
}

private struct ExportedAttachment: Encodable {
  let name: String?
  let url: String
  let type: String?
  let size: Int64?

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(name, forKey: .name)
    try container.encode(url, forKey: .url)
    try container.encode(type, forKey: .type)
    try container.encode(size, forKey: .size)
  }

  private enum CodingKeys: String, CodingKey { case name, url, type, size }
}
