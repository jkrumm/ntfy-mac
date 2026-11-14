import Foundation

/// Finds more than one copy of `NtfyMac.app` on this Mac. Two copies share a bundle id and fight
/// over the login item, notification permission and the socket. Pure over the paths it is given.
struct DuplicateInstall: Sendable {
  enum Channel: String, Sendable {
    case homebrew = "Homebrew"
    case direct = "direct"
  }

  struct Copy: Equatable, Sendable {
    /// The path as found, e.g. `~/Applications/NtfyMac.app`.
    let path: String
    /// The path after resolving links; what identifies the copy.
    let realPath: String
    let channel: Channel
    let isRunning: Bool
  }

  /// The places a copy can live: both Applications folders and Homebrew's `opt` link on both
  /// prefixes.
  static func candidates(home: URL, brewPrefixes: [String] = ["/opt/homebrew", "/usr/local"])
    -> [URL]
  {
    [
      home.appending(path: "Applications/NtfyMac.app", directoryHint: .isDirectory),
      URL(filePath: "/Applications/NtfyMac.app", directoryHint: .isDirectory),
    ]
      + brewPrefixes.map {
        URL(filePath: $0).appending(path: "opt/ntfy-mac/NtfyMac.app", directoryHint: .isDirectory)
      }
  }

  /// The distinct copies among `candidates`, in order. A link into another copy is that copy.
  static func copies(among candidates: [URL], runningExecutable: String) -> [Copy] {
    let running = URL(filePath: runningExecutable).resolvingSymlinksInPath().path
    var seen = Set<String>()
    var result: [Copy] = []
    for candidate in candidates {
      guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
      let real = candidate.resolvingSymlinksInPath().path
      guard seen.insert(real).inserted else { continue }
      result.append(
        Copy(
          path: candidate.path, realPath: real,
          channel: real.contains("/Cellar/") ? .homebrew : .direct,
          isRunning: running.hasPrefix(real + "/")))
    }
    return result
  }

  static func check(candidates: [URL], runningExecutable: String) -> DoctorCheck {
    let found = copies(among: candidates, runningExecutable: runningExecutable)
    guard found.count > 1 else {
      return DoctorCheck("duplicate-install", .passed, "One copy of NtfyMac.app")
    }
    let list = found.map {
      "  \($0.path) (\($0.channel.rawValue))\($0.isRunning ? " <- running" : "")"
    }
    let running =
      found.first(where: \.isRunning).map { "This ntfy-mac runs from \($0.path)." }
      ?? "This ntfy-mac runs from none of them."
    return DoctorCheck(
      "duplicate-install", .warn, "\(found.count) copies of NtfyMac.app",
      detail: """
        \(list.joined(separator: "\n"))
        \(running)
        Keep one. Homebrew copy: brew uninstall --cask ntfy-mac (the old formula: brew uninstall --formula \
        ntfy-mac). Direct copy: delete the app and the ~/.local/bin/ntfy-mac link. Config and history stay.
        """)
  }
}
