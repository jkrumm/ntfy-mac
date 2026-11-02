import Foundation

/// Why notifications are held back as a meeting.
public enum MeetingReason: Sendable, Hashable {
  /// A dedicated meeting app (Zoom, Teams, Webex, FaceTime) is using the microphone.
  case app(String)
  /// Slack is using the microphone and speakers at once, which only a huddle does.
  case slackHuddle
  /// A browser is using the microphone while the camera runs.
  case browserCall(String)
  /// The user said so (`ntfy-mac present on`).
  case presenting

  /// A stable lowercase code for the CLI and the socket.
  public var code: String {
    switch self {
    case .app: "app"
    case .slackHuddle: "huddle"
    case .browserCall: "browser"
    case .presenting: "presenting"
    }
  }

  /// The app behind the reason, nil for a manual override.
  public var detail: String? {
    switch self {
    case .app(let name), .browserCall(let name): name
    case .slackHuddle: "Slack"
    case .presenting: nil
    }
  }

  /// A short phrase for the menu and `status`.
  public var summary: String {
    switch self {
    case .app(let name): name
    case .slackHuddle: "Slack huddle"
    case .browserCall(let name): "\(name) call"
    case .presenting: "presenting"
    }
  }
}

/// Whether a meeting is going on.
public enum MeetingState: Sendable, Hashable {
  case inactive
  case active(MeetingReason)

  public var isActive: Bool { reason != nil }

  public var reason: MeetingReason? {
    guard case .active(let reason) = self else { return nil }
    return reason
  }
}

extension MeetingSettings {
  /// The meeting state that holds notifications back right now. The manual override wins over
  /// detection and works with `mode` off, because it is an explicit action; detection counts
  /// only when `mode` is `pause`.
  public func effectiveState(detected: MeetingState, at now: Date) -> MeetingState {
    if isPresenting(at: now) { return .active(.presenting) }
    return mode == .pause ? detected : .inactive
  }
}

/// Whether a camera is capturing, in any app. It does not say which.
public enum CameraState: Sendable, Hashable {
  case running
  case idle
  /// The reading failed.
  case unknown
}

/// What the app can see of the machine, read once. `nil` means the reading failed: that is
/// unknown, never "no".
public struct MeetingSnapshot: Sendable, Hashable {
  /// Every process that has registered with the audio system.
  public var audio: [AudioProcessState]?
  public var camera: CameraState
  /// Bundle identifiers of the running applications.
  public var runningApps: Set<String>
  /// This process, which never counts.
  public var ownPID: Int32?

  public init(
    audio: [AudioProcessState]? = [], camera: CameraState = .idle,
    runningApps: Set<String> = [], ownPID: Int32? = nil
  ) {
    self.audio = audio
    self.camera = camera
    self.runningApps = runningApps
    self.ownPID = ownPID
  }
}

/// One process in the audio system.
public struct AudioProcessState: Sendable, Hashable {
  public var pid: Int32
  /// Empty for a process without a bundle (a command-line tool).
  public var bundleID: String
  public var isRunningInput: Bool
  public var isRunningOutput: Bool

  public init(pid: Int32, bundleID: String, isRunningInput: Bool, isRunningOutput: Bool) {
    self.pid = pid
    self.bundleID = bundleID
    self.isRunningInput = isRunningInput
    self.isRunningOutput = isRunningOutput
  }
}

/// Where the monitor reads the machine from.
public protocol MeetingSignalSource: Sendable {
  /// A reading now.
  func snapshot() async -> MeetingSnapshot
  /// One element each time the audio or camera state may have changed. A source that cannot
  /// say returns a stream that never yields; the monitor polls anyway.
  func changes() -> AsyncStream<Void>
}

/// The detected meeting state, without the manual override (`MeetingSettings.effectiveState`).
public protocol MeetingStateProviding: Sendable {
  func current() async -> MeetingState
  /// The state at subscription time, then every change.
  func changes() -> AsyncStream<MeetingState>
}
