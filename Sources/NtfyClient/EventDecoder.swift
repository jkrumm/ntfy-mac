import Foundation
import NtfyCore

private struct WireEvent: Decodable {
  let id: String
  let time: TimeInterval
  let event: String
  let topic: String
  let sequenceID: String?
  let message: String?
  let title: String?
  let priority: Int?
  let tags: [String]?
  let click: URL?

  private enum CodingKeys: String, CodingKey {
    case id, time, event, topic, message, title, priority, tags, click
    case sequenceID = "sequence_id"
  }
}

/// Decodes one line of ntfy's `/json` stream.
public enum EventDecoder {
  /// Returns `nil` for event types this client does not know, so newer servers cannot break it.
  /// A line that is not a well-formed event throws `.invalidResponse`.
  public static func decode(line: Data) throws(NtfyError) -> StreamEvent? {
    let event: WireEvent
    do {
      event = try JSONDecoder().decode(WireEvent.self, from: line)
    } catch {
      throw .invalidResponse("undecodable stream line")
    }
    switch event.event {
    case "open": return .open
    case "keepalive": return .keepalive
    case "poll_request": return .pollRequest
    case "message": return .message(message(from: event))
    case "message_delete", "message_clear":
      guard let sequenceID = event.sequenceID else {
        throw .invalidResponse("\(event.event) without sequence_id")
      }
      return event.event == "message_delete"
        ? .messageDelete(topic: event.topic, sequenceID: sequenceID)
        : .messageClear(topic: event.topic, sequenceID: sequenceID)
    default: return nil
    }
  }

  private static func message(from event: WireEvent) -> NtfyMessage {
    NtfyMessage(
      id: event.id,
      topic: event.topic,
      time: Date(timeIntervalSince1970: event.time),
      title: event.title,
      body: event.message ?? "",
      priority: Priority(clamping: event.priority ?? Priority.default.rawValue),
      tags: event.tags ?? [],
      click: event.click,
      sequenceID: event.sequenceID
    )
  }
}
