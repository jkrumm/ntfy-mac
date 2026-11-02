/// The applications whose audio and camera use counts as a meeting, by bundle identifier.
///
/// Audio is often held by a helper process (a browser's GPU or media helper, an Electron
/// helper), so identifiers match by prefix at a dot boundary: `com.google.Chrome` matches
/// `com.google.Chrome.helper` but not `com.google.Chromium`.
enum MeetingAppCatalog {
  enum Kind: Sendable {
    /// Holding the microphone is the meeting.
    case dedicated
    /// Open all day; only a huddle uses the microphone and the speakers together.
    case slack
    /// Holding the microphone with the camera running is a probable call.
    case browser
  }

  struct Entry: Sendable {
    let name: String
    let kind: Kind
    let prefixes: [String]
    /// The helper identifiers that name no app (Safari's WebKit processes) count only while one
    /// of these is running.
    let sharedHelpers: [String]
    let requiresRunning: String?

    init(
      _ name: String, _ kind: Kind, _ prefixes: [String], sharedHelpers: [String] = [],
      requiresRunning: String? = nil
    ) {
      self.name = name
      self.kind = kind
      self.prefixes = prefixes
      self.sharedHelpers = sharedHelpers
      self.requiresRunning = requiresRunning
    }
  }

  // Zoom, Slack, Chrome, Vivaldi, Helium and Safari were read off real installs; Teams and
  // Webex from vendor documentation (Webex's is the preferences domain of the Mac app).
  static let entries: [Entry] = [
    Entry("Zoom", .dedicated, ["us.zoom.xos"]),
    Entry("Microsoft Teams", .dedicated, ["com.microsoft.teams2", "com.microsoft.teams"]),
    Entry("Webex", .dedicated, ["Cisco-Systems.Spark"]),
    Entry("FaceTime", .dedicated, ["com.apple.FaceTime"]),
    Entry("Slack", .slack, ["com.tinyspeck.slackmacgap"]),
    Entry("Google Chrome", .browser, ["com.google.Chrome"]),
    Entry(
      "Safari", .browser, [], sharedHelpers: ["com.apple.WebKit.GPU"],
      requiresRunning: "com.apple.Safari"),
    Entry("Firefox", .browser, ["org.mozilla.firefox"]),
    Entry("Microsoft Edge", .browser, ["com.microsoft.edgemac"]),
    Entry("Brave", .browser, ["com.brave.Browser"]),
    Entry("Arc", .browser, ["company.thebrowser.Browser"]),
    Entry("Vivaldi", .browser, ["com.vivaldi.Vivaldi"]),
    Entry("Helium", .browser, ["net.imput.helium"]),
  ]

  /// Processes that hold the microphone for the system, not for a meeting.
  static let excluded: [String] = [
    "com.apple.CoreSpeech", "com.apple.Siri", "com.apple.assistantd", "com.jkrumm.ntfy-mac",
  ]

  static func matches(_ bundleID: String, prefix: String) -> Bool {
    bundleID == prefix || bundleID.hasPrefix(prefix + ".")
  }

  static func isExcluded(_ bundleID: String) -> Bool {
    excluded.contains { matches(bundleID, prefix: $0) }
  }

  /// The entry a process belongs to, nil for any other process.
  static func entry(forBundleID bundleID: String, runningApps: Set<String>) -> Entry? {
    entries.first { entry in
      if entry.prefixes.contains(where: { matches(bundleID, prefix: $0) }) { return true }
      guard entry.sharedHelpers.contains(where: { matches(bundleID, prefix: $0) }) else {
        return false
      }
      return entry.requiresRunning.map(runningApps.contains) ?? true
    }
  }
}
