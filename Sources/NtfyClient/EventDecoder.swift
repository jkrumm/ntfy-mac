import Foundation
import NtfyCore

/// Decodes one line of ntfy's `/json` stream.
public enum EventDecoder {
  private struct Event: Decodable {
    let id: String
    let time: TimeInterval
    let event: String
    let topic: String
    let message: String?
    let title: String?
    let priority: Int?
    let tags: [String]?
    let click: URL?
  }

  /// Returns the message for `message` events, `nil` for keepalives and other events.
  public static func decode(line: Data) throws(NtfyError) -> NtfyMessage? {
    let event: Event
    do {
      event = try JSONDecoder().decode(Event.self, from: line)
    } catch {
      throw .invalidResponse("undecodable stream line")
    }
    guard event.event == "message" else { return nil }
    return NtfyMessage(
      id: event.id,
      topic: event.topic,
      time: Date(timeIntervalSince1970: event.time),
      title: event.title,
      body: event.message ?? "",
      priority: Priority(clamping: event.priority ?? Priority.default.rawValue),
      tags: event.tags ?? [],
      click: event.click
    )
  }
}
