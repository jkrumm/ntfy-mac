import Foundation

/// A throwaway directory under the system temp dir; tests never touch the real home.
struct TempDirectory: ~Copyable {
  let url: URL

  init() {
    url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ntfy-mac-tests-\(UUID().uuidString)", isDirectory: true)
  }

  deinit { try? FileManager.default.removeItem(at: url) }

  func file(_ name: String) -> URL { url.appendingPathComponent(name) }

  func write(_ content: String, to name: String) throws {
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data(content.utf8).write(to: file(name))
  }

  func read(_ name: String) throws -> String {
    String(bytes: try Data(contentsOf: file(name)), encoding: .utf8) ?? ""
  }

  func permissions(_ path: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
    return (attributes[.posixPermissions] as? Int) ?? -1
  }
}
