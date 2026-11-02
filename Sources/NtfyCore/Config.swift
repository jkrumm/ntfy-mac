import Foundation

/// User-editable settings (the 2.0 subset the ports need so far).
public struct Config: Sendable, Hashable, Codable {
  public var url: URL?
  public var topics: [String]

  public init(url: URL? = nil, topics: [String] = []) {
    self.url = url
    self.topics = topics
  }
}
