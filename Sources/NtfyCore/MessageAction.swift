import Foundation

/// An action button a sender attached to a message.
public struct MessageAction: Sendable, Hashable, Codable {
  public enum Kind: Sendable, Hashable, Codable {
    case view, http, broadcast, copy
    case unknown(String)

    public init(name: String) {
      switch name {
      case "view": self = .view
      case "http": self = .http
      case "broadcast": self = .broadcast
      case "copy": self = .copy
      default: self = .unknown(name)
      }
    }

    public var name: String {
      switch self {
      case .view: "view"
      case .http: "http"
      case .broadcast: "broadcast"
      case .copy: "copy"
      case .unknown(let name): name
      }
    }

    public init(from decoder: any Decoder) throws {
      self.init(name: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
      var container = encoder.singleValueContainer()
      try container.encode(name)
    }
  }

  public let id: String?
  public let kind: Kind
  public let label: String
  public let url: URL?
  public let method: String?
  public let headers: [String: String]
  public let body: String?
  /// The sender wants the notification cleared once the action ran.
  public let clear: Bool

  public init(
    id: String? = nil,
    kind: Kind,
    label: String,
    url: URL? = nil,
    method: String? = nil,
    headers: [String: String] = [:],
    body: String? = nil,
    clear: Bool = false
  ) {
    self.id = id
    self.kind = kind
    self.label = label
    self.url = url
    self.method = method
    self.headers = headers
    self.body = body
    self.clear = clear
  }

  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id)
    kind = try container.decode(Kind.self, forKey: .kind)
    label = try container.decode(String.self, forKey: .label)
    url = try container.decodeIfPresent(URL.self, forKey: .url)
    method = try container.decodeIfPresent(String.self, forKey: .method)
    headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
    body = try container.decodeIfPresent(String.self, forKey: .body)
    clear = try container.decodeIfPresent(Bool.self, forKey: .clear) ?? false
  }
}
