import Foundation

/// A file the server hosts for a message.
public struct MessageAttachment: Sendable, Hashable, Codable {
  public let url: URL
  public let name: String?
  public let mimeType: String?
  public let size: Int64?
  public let expires: Date?

  public init(
    url: URL, name: String? = nil, mimeType: String? = nil, size: Int64? = nil,
    expires: Date? = nil
  ) {
    self.url = url
    self.name = name
    self.mimeType = mimeType
    self.size = size
    self.expires = expires
  }

  public var isImage: Bool { mimeType?.lowercased().hasPrefix("image/") ?? false }
}
