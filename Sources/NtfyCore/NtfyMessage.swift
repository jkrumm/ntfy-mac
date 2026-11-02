import Foundation

/// A message received from, or destined for, an ntfy topic.
public struct NtfyMessage: Sendable, Hashable, Codable, Identifiable {
  public let id: String
  public let topic: String
  public let time: Date
  public let title: String?
  public let body: String
  public let priority: Priority
  public let tags: [String]
  public let click: URL?

  public init(
    id: String,
    topic: String,
    time: Date,
    title: String? = nil,
    body: String,
    priority: Priority = .default,
    tags: [String] = [],
    click: URL? = nil
  ) {
    self.id = id
    self.topic = topic
    self.time = time
    self.title = title
    self.body = body
    self.priority = priority
    self.tags = tags
    self.click = click
  }
}
