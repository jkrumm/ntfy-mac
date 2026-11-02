import Foundation
import NtfyCore

/// Decodes to `nil` instead of throwing, so one malformed optional sub-object of an event is
/// dropped without losing the message around it.
struct Lenient<Value: Decodable>: Decodable {
  let value: Value?

  init(from decoder: any Decoder) throws {
    value = try? decoder.singleValueContainer().decode(Value.self)
  }
}

struct WireAttachment: Decodable {
  let name: String?
  let url: URL
  let type: String?
  let size: Int64?
  let expires: TimeInterval?

  var model: MessageAttachment {
    MessageAttachment(
      url: url, name: name, mimeType: type, size: size,
      expires: expires.map { Date(timeIntervalSince1970: $0) })
  }
}

struct WireAction: Decodable {
  let id: String?
  let action: String
  let label: String
  let clear: Lenient<Bool>?
  let url: URL?
  let method: String?
  let headers: [String: String]?
  let body: String?

  var model: MessageAction {
    MessageAction(
      id: id, kind: .init(name: action), label: label, url: url, method: method,
      headers: headers ?? [:], body: body, clear: clear?.value ?? false)
  }
}
