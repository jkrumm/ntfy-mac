import Foundation
import NtfyCore
import NtfyIPC

/// Builds the notification payload from `notify` flags or from the JSON on stdin. Field names are
/// the 1.x ones (`title`, `body`, `priority`, `tags`, `clickUrl`, `dismissAfter`); `message`,
/// `click`, `url` and `dismiss` are accepted as aliases.
enum NotifyInput {
  static let defaultTitle = "ntfy-mac"

  static func payload(json: Data) throws -> NotifyPayload {
    guard !json.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) else {
      throw CLIFailure.usage("--json requires a JSON payload on stdin.")
    }
    guard let object = ConfigValue.parseObject(json) else {
      throw CLIFailure.usage("Invalid JSON on stdin: expected one JSON object.")
    }
    let body = (object["body"] ?? object["message"])?.stringValue ?? ""
    guard !body.isEmpty else { throw CLIFailure.usage("The JSON payload needs a \"body\" field.") }
    let url = (object["clickUrl"] ?? object["click"] ?? object["url"])?.stringValue
    return try NotifyPayload(
      title: object["title"]?.stringValue ?? defaultTitle,
      body: body,
      priority: try priority(object["priority"]),
      tags: tags(object["tags"]),
      clickURL: url.map(clickURL),
      dismissAfterSeconds: try dismiss(object["dismissAfter"] ?? object["dismiss"]))
  }

  /// Only web and mail links open from a notification (`URLPolicy`).
  static func clickURL(_ text: String) throws -> URL {
    guard let url = URL(string: text), let allowed = URLPolicy.openable(url) else {
      throw CLIFailure.usage("The click URL must be http, https or mailto: \(text)")
    }
    return allowed
  }

  private static func priority(_ value: ConfigValue?) throws -> Int {
    guard let value else { return Priority.default.rawValue }
    guard let number = value.intValue, Priority.range.contains(number) else {
      throw CLIFailure.usage("The priority must be a whole number from 1 to 5.")
    }
    return number
  }

  private static func tags(_ value: ConfigValue?) -> [String] {
    switch value {
    case .array(let items)?: items.compactMap(\.stringValue)
    case .string(let text)?:
      text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter {
        !$0.isEmpty
      }
    default: []
    }
  }

  private static func dismiss(_ value: ConfigValue?) throws -> Double? {
    guard let value else { return nil }
    guard let seconds = value.numberValue, seconds >= 0 else {
      throw CLIFailure.usage("The dismiss time must be a number of seconds, 0 or more.")
    }
    return seconds
  }
}
