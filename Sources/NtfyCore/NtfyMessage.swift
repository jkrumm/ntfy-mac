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
  /// Groups updates of one notification; the server omits it when it equals `id`.
  public let sequenceID: String?
  public let icon: URL?
  public let attachment: MessageAttachment?
  public let actions: [MessageAction]
  public let expires: Date?
  /// The server's `content_type`; `text/markdown` marks a markdown body. Nil when not sent.
  public let contentType: String?

  public init(
    id: String,
    topic: String,
    time: Date,
    title: String? = nil,
    body: String,
    priority: Priority = .default,
    tags: [String] = [],
    click: URL? = nil,
    sequenceID: String? = nil,
    icon: URL? = nil,
    attachment: MessageAttachment? = nil,
    actions: [MessageAction] = [],
    expires: Date? = nil,
    contentType: String? = nil
  ) {
    self.id = id
    self.topic = topic
    self.time = time
    self.title = title
    self.body = body
    self.priority = priority
    self.tags = tags
    self.click = click
    self.sequenceID = sequenceID
    self.icon = icon
    self.attachment = attachment
    self.actions = actions
    self.expires = expires
    self.contentType = contentType
  }

  /// The body is markdown (`text/markdown`, parameters such as a charset ignored).
  public var isMarkdown: Bool {
    guard let contentType else { return false }
    let media = contentType.split(separator: ";").first ?? ""
    return media.trimmingCharacters(in: .whitespaces).lowercased() == "text/markdown"
  }

  /// Rows stored before a field existed still decode: every later addition is optional here.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decode(String.self, forKey: .id)
    topic = try container.decode(String.self, forKey: .topic)
    time = try container.decode(Date.self, forKey: .time)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    body = try container.decode(String.self, forKey: .body)
    priority = try container.decodeIfPresent(Priority.self, forKey: .priority) ?? .default
    tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    click = try container.decodeIfPresent(URL.self, forKey: .click)
    sequenceID = try container.decodeIfPresent(String.self, forKey: .sequenceID)
    icon = try container.decodeIfPresent(URL.self, forKey: .icon)
    attachment = try container.decodeIfPresent(MessageAttachment.self, forKey: .attachment)
    actions = try container.decodeIfPresent([MessageAction].self, forKey: .actions) ?? []
    expires = try container.decodeIfPresent(Date.self, forKey: .expires)
    contentType = try container.decodeIfPresent(String.self, forKey: .contentType)
  }
}
