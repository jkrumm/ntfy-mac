import Foundation
import NtfyCore

/// The resume cursor in the 1.x `state.json` (`lastMessageId`).
///
/// 2.0 reads and writes only that key; everything else in the file (`seen`, reminders, ...) is
/// preserved. A missing or corrupt file is simply "no cursor": `load` never fails on content, and
/// `save` starts a fresh file over a corrupt one (state is disposable, a stuck cursor is worse).
public actor FileCursorStore: CursorStore {
  private static let key = "lastMessageId"

  public static var defaultURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".local/share/ntfy-mac/state.json")
  }

  private let url: URL

  public init(url: URL = FileCursorStore.defaultURL) {
    self.url = url
  }

  public func load() throws(NtfyError) -> String? {
    guard let object = try readObject(), let id = object[Self.key]?.stringValue, !id.isEmpty else {
      return nil
    }
    return id
  }

  public func save(_ id: String) throws(NtfyError) {
    var object = try readObject() ?? [:]
    if object[Self.key] == .string(id) { return }
    object[Self.key] = .string(id)
    try AtomicFile.write(try ConfigValue.encodeObject(object), to: url)
  }

  /// Nil when the file is missing or corrupt. An unreadable file (permissions) still throws.
  private func readObject() throws(NtfyError) -> [String: ConfigValue]? {
    guard let data = try AtomicFile.read(url) else { return nil }
    return ConfigValue.parseObject(data)
  }
}
