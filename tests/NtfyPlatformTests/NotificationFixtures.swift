import Foundation
import NtfyCore

enum NotificationFixtures {
  static let time = Date(timeIntervalSince1970: 1_700_000_000)

  static func message(
    id: String = "abc12345", topic: String = "alerts", priority: Priority = .default,
    image: URL? = nil, actions: [MessageAction] = []
  ) -> NtfyMessage {
    NtfyMessage(
      id: id, topic: topic, time: time, title: "Disk", body: "body", priority: priority,
      attachment: image.map {
        MessageAttachment(url: $0, name: "i.png", mimeType: "image/png")
      }, actions: actions)
  }

  static func content(
    _ message: NtfyMessage = message(), config: Config = Config()
  ) -> NotificationContent {
    DeliveryPolicy.content(for: message, config: config)
  }

  static func viewAction(_ label: String) -> MessageAction {
    MessageAction(kind: .view, label: label, url: URL(string: "https://example.com/\(label)"))
  }

  /// A valid 1x1 PNG on disk, in a directory of its own.
  static func pngFile() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ntfy-mac-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("image.png")
    let base64 =
      "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    try Data(base64Encoded: base64)?.write(to: file)
    return file
  }
}
