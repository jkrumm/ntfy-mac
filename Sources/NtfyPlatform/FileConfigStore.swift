import Foundation
import NtfyCore

/// `config.json` on disk, compatible with the 1.x file.
///
/// - A missing, unreadable or malformed file loads as an empty `Config`, as in 1.x.
/// - A write refuses to replace a malformed file (`NtfyError.storage`): the user's hand edits
///   are not silently destroyed. An empty file is overwritten, there is nothing to lose.
/// - Unknown keys round-trip through `Config.extras`.
/// - Writes are atomic, the file is mode 600 and its directory 700.
/// - Writes hold an `flock` on the sidecar `config.json.lock`, so the app and the CLI (separate
///   processes) never lose each other's update.
public actor FileConfigStore: ConfigStore {
  public static var defaultURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent(".config/ntfy-mac/config.json")
  }

  private let url: URL

  public init(url: URL = FileConfigStore.defaultURL) {
    self.url = url
  }

  public func load() -> Config {
    guard let data = try? AtomicFile.read(url), let config = Config.parse(data) else {
      return Config()
    }
    return config
  }

  /// Like `load`, but a file that exists and is neither blank nor valid JSON, or cannot be read,
  /// is an error instead of an empty config. Callers that act on "nothing configured" use this,
  /// so a half-written file is not mistaken for a cleared one.
  public func loadChecked() async throws(NtfyError) -> Config {
    guard let data = try AtomicFile.read(url) else { return Config() }
    if data.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) {
      return Config()
    }
    guard let config = Config.parse(data) else {
      throw .storage("\(url.lastPathComponent) is not valid JSON")
    }
    return config
  }

  public func save(_ config: Config) throws(NtfyError) {
    try FileLock.withExclusive(lockURL) { () throws(NtfyError) in
      try refuseToClobberMalformedFile()
      try AtomicFile.write(try config.serialized(), to: url)
    }
  }

  /// Read-modify-write inside the actor and under the file lock, so neither a concurrent
  /// in-process update nor one from another process can be lost.
  public func update(_ change: @Sendable (inout Config) -> Void) throws(NtfyError) {
    try FileLock.withExclusive(lockURL) { () throws(NtfyError) in
      try refuseToClobberMalformedFile()
      var config = load()
      change(&config)
      try AtomicFile.write(try config.serialized(), to: url)
    }
  }

  private var lockURL: URL { url.appendingPathExtension("lock") }

  private func refuseToClobberMalformedFile() throws(NtfyError) {
    guard let data = try AtomicFile.read(url) else { return }
    let blank = data.allSatisfy { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
    guard blank || Config.parse(data) != nil else {
      throw .storage("\(url.lastPathComponent) is not valid JSON; fix or remove it first")
    }
  }
}
