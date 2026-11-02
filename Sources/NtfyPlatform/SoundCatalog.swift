import Foundation

public struct Sound: Sendable, Hashable {
  public let name: String
  public let file: URL
}

/// The sounds macOS can play for a notification: `.aiff`, `.wav` and `.caf` files in the system
/// and user sound directories.
public enum SoundCatalog {
  public static let silent = "silent"
  private static let extensions: Set<String> = ["aiff", "wav", "caf"]

  /// The system sounds, then the user's own in `~/Library/Sounds`.
  public static func directories(home: URL) -> [URL] {
    [
      URL(fileURLWithPath: "/System/Library/Sounds", isDirectory: true),
      home.appending(path: "Library/Sounds", directoryHint: .isDirectory),
    ]
  }

  /// Sorted by name, one entry per name; the first directory wins.
  public static func sounds(in directories: [URL]) -> [Sound] {
    var byName: [String: Sound] = [:]
    for directory in directories {
      let files =
        (try? FileManager.default.contentsOfDirectory(
          at: directory, includingPropertiesForKeys: nil)) ?? []
      for file in files where extensions.contains(file.pathExtension.lowercased()) {
        let name = file.deletingPathExtension().lastPathComponent
        if byName[name] == nil { byName[name] = Sound(name: name, file: file) }
      }
    }
    return byName.values.sorted { $0.name < $1.name }
  }
}
