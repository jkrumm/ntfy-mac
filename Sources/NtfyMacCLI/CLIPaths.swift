import Foundation
import NtfyIPC
import NtfyPlatform
import NtfyStore

/// Every location the CLI reads or writes, derived from the home directory and two overrides,
/// so tests never touch the real ones.
struct CLIPaths: Sendable, Hashable {
  /// Replaces `~/.config/ntfy-mac`.
  static let configDirectoryVariable = "NTFY_MAC_CONFIG_DIR"
  /// Replaces `~/Library/Application Support` and `~/.local/share/ntfy-mac`: history, socket and
  /// 1.x state all live below it.
  static let dataDirectoryVariable = "NTFY_MAC_DATA_DIR"

  var configFile: URL
  /// Holds the `ntfy-mac` directory with the history database and the socket.
  var applicationSupport: URL
  /// The 1.x state directory (`state.json`, old logs).
  var stateDirectory: URL
  var soundDirectories: [URL]

  init(environment: [String: String], home: URL, systemApplicationSupport: URL) {
    let configDirectory =
      environment[Self.configDirectoryVariable].flatMap(Self.directory)
      ?? home.appending(path: ".config/ntfy-mac", directoryHint: .isDirectory)
    configFile = configDirectory.appending(path: "config.json", directoryHint: .notDirectory)
    if let data = environment[Self.dataDirectoryVariable].flatMap(Self.directory) {
      applicationSupport = data
      stateDirectory = data.appending(path: "state", directoryHint: .isDirectory)
    } else {
      applicationSupport = systemApplicationSupport
      stateDirectory = home.appending(path: ".local/share/ntfy-mac", directoryHint: .isDirectory)
    }
    soundDirectories = SoundCatalog.directories(home: home)
  }

  static func live(environment: [String: String]) -> CLIPaths {
    let home = FileManager.default.homeDirectoryForCurrentUser
    let support =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? home.appending(path: "Library/Application Support", directoryHint: .isDirectory)
    return CLIPaths(environment: environment, home: home, systemApplicationSupport: support)
  }

  var configDirectory: URL { configFile.deletingLastPathComponent() }
  var configLock: URL { configFile.appendingPathExtension("lock") }
  /// The app's own directory: history database, socket.
  var dataDirectory: URL {
    applicationSupport.appending(path: StoreLocation.directoryName, directoryHint: .isDirectory)
  }
  var socket: URL { SocketPath.default(applicationSupport: applicationSupport) }
  var databaseURL: URL { StoreLocation.databaseURL(applicationSupport: applicationSupport) }

  private static func directory(_ path: String) -> URL? {
    path.isEmpty ? nil : URL(fileURLWithPath: path, isDirectory: true)
  }
}
