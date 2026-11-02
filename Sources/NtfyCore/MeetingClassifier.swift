/// What one reading says.
enum MeetingVerdict: Sendable, Hashable {
  case meeting(MeetingReason)
  case none
  /// A reading that the rules need failed and nothing else decided it.
  case unknown
}

/// The rules that turn one reading into a verdict, with no memory and no clock.
///
/// - A dedicated meeting app holding the microphone is a meeting.
/// - Slack counts only with microphone and speakers in use at once (a huddle).
/// - A browser counts only with the microphone in use and a camera running; the page is never
///   looked at. Audio-only calls in a browser are not detected.
/// - A camera alone, or audio output alone, never counts.
/// - This process and the system's own microphone users never count.
enum MeetingClassifier {
  static func verdict(for snapshot: MeetingSnapshot) -> MeetingVerdict {
    guard let audio = snapshot.audio else { return .unknown }
    var use = Use()
    for process in audio where counts(process, in: snapshot) {
      guard
        let entry = MeetingAppCatalog.entry(
          forBundleID: process.bundleID, runningApps: snapshot.runningApps)
      else { continue }
      if let app = use.add(process, of: entry) { return .meeting(.app(app)) }
    }
    if use.slackInput, use.slackOutput { return .meeting(.slackHuddle) }
    guard let browser = use.browser else { return .none }
    switch snapshot.camera {
    case .running: return .meeting(.browserCall(browser))
    case .idle: return .none
    case .unknown: return .unknown
    }
  }

  private static func counts(_ process: AudioProcessState, in snapshot: MeetingSnapshot) -> Bool {
    if let own = snapshot.ownPID, process.pid == own { return false }
    return !MeetingAppCatalog.isExcluded(process.bundleID)
  }

  /// What the matching processes were seen doing so far.
  private struct Use {
    var slackInput = false
    var slackOutput = false
    var browser: String?

    /// Notes the process; returns the app's name when it alone makes a meeting.
    mutating func add(_ process: AudioProcessState, of entry: MeetingAppCatalog.Entry) -> String? {
      switch entry.kind {
      case .dedicated:
        return process.isRunningInput ? entry.name : nil
      case .slack:
        slackInput = slackInput || process.isRunningInput
        slackOutput = slackOutput || process.isRunningOutput
      case .browser:
        if process.isRunningInput, browser == nil { browser = entry.name }
      }
      return nil
    }
  }
}
