import Foundation

/// Where a 1.x install (curl, Homebrew or dev) leaves its files. Everything derives from the
/// home directory, so tests point it at a temp directory.
public struct LegacyInstallLayout: Sendable, Equatable {
  public static let curlLabel = "com.jkrumm.ntfy-mac"
  public static let brewLabel = "homebrew.mxcl.ntfy-mac"
  public static let helperName = "ntfy-notify.app"
  public static let formulaName = "ntfy-mac"
  static let logNames = ["ntfy-mac.log", "ntfy-mac-error.log"]

  public let uid: UInt32
  public let launchAgents: URL
  /// `~/.local/share/ntfy-mac`: pid file, logs, the curl install's helper. Holds `config.json`
  /// and `state.json` too, which cleanup never touches.
  public let stateDirectory: URL
  public let userApplications: URL
  public let curlBinary: URL
  /// Homebrew prefixes to look in (`/opt/homebrew`, `/usr/local`).
  public let brewPrefixes: [URL]

  public init(
    home: URL, uid: UInt32, stateDirectory: URL? = nil,
    brewPrefixes: [URL] = [
      URL(fileURLWithPath: "/opt/homebrew", isDirectory: true),
      URL(fileURLWithPath: "/usr/local", isDirectory: true),
    ]
  ) {
    self.uid = uid
    launchAgents = home.appending(path: "Library/LaunchAgents", directoryHint: .isDirectory)
    self.stateDirectory =
      stateDirectory ?? home.appending(path: ".local/share/ntfy-mac", directoryHint: .isDirectory)
    userApplications = home.appending(path: "Applications", directoryHint: .isDirectory)
    curlBinary = home.appending(path: ".local/bin/ntfy-mac", directoryHint: .notDirectory)
    self.brewPrefixes = brewPrefixes
  }

  public func plist(label: String) -> URL {
    launchAgents.appending(path: "\(label).plist", directoryHint: .notDirectory)
  }

  var pidFile: URL { stateDirectory.appending(path: "ntfy-mac.pid", directoryHint: .notDirectory) }

  var curlHelper: URL {
    stateDirectory.appending(path: Self.helperName, directoryHint: .isDirectory)
  }

  var devHelper: URL {
    userApplications.appending(path: Self.helperName, directoryHint: .isDirectory)
  }

  var logs: [URL] {
    Self.logNames.map { stateDirectory.appending(path: $0, directoryHint: .notDirectory) }
  }

  /// The helper inside each Homebrew keg, plus the `opt` link's when it points somewhere the
  /// Cellar scan did not already find. A `brew upgrade` normally removes the old keg.
  func brewHelpers() -> [URL] {
    let manager = FileManager.default
    var found: [URL] = []
    var seen: Set<String> = []
    for prefix in brewPrefixes {
      let cellar = prefix.appending(path: "Cellar/\(Self.formulaName)", directoryHint: .isDirectory)
      let kegs =
        (try? manager.contentsOfDirectory(atPath: cellar.path))?.sorted() ?? []
      var candidates = kegs.map {
        cellar.appending(path: "\($0)/libexec/\(Self.helperName)", directoryHint: .isDirectory)
      }
      candidates.append(
        prefix.appending(
          path: "opt/\(Self.formulaName)/libexec/\(Self.helperName)", directoryHint: .isDirectory))
      for candidate in candidates where LegacyFiles.exists(candidate) {
        guard seen.insert(candidate.resolvingSymlinksInPath().path).inserted else { continue }
        found.append(candidate)
      }
    }
    return found
  }
}

/// Small filesystem questions the cleanup asks.
enum LegacyFiles {
  /// True for anything at the path, including a dangling symlink.
  static func exists(_ url: URL) -> Bool {
    (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
  }

  /// A regular file (not a symlink) whose first bytes are a Mach-O or fat-binary magic.
  static func isRegularMachO(_ url: URL) -> Bool {
    guard
      let type = try? FileManager.default.attributesOfItem(atPath: url.path)[.type]
        as? FileAttributeType,
      type == .typeRegular,
      let handle = try? FileHandle(forReadingFrom: url)
    else { return false }
    defer { try? handle.close() }
    guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
    let magic = [UInt8](head)
    let known: [[UInt8]] = [
      [0xCF, 0xFA, 0xED, 0xFE], [0xCE, 0xFA, 0xED, 0xFE],
      [0xCA, 0xFE, 0xBA, 0xBE], [0xBE, 0xBA, 0xFE, 0xCA],
    ]
    return known.contains(magic)
  }
}
