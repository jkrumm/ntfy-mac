/// Why this copy does not update itself. The raw values are the stable names of the wire format
/// and of `ntfy-mac update --json`.
public enum UpdateUnavailableReason: String, Sendable, Codable, Hashable, CaseIterable {
  /// Installed by Homebrew; `brew upgrade` updates it.
  case homebrew
  /// Not Developer-ID signed (a development or ad-hoc build): Sparkle would refuse the update.
  case unsigned
  /// `NTFY_MAC_NO_SELF_UPDATE=1`.
  case disabled
  /// Signed by another team than the first signed run.
  case teamMismatch = "team-mismatch"
}

/// The state of updating, as the app reports it.
public struct UpdateStatus: Sendable, Codable, Hashable {
  public let channel: InstallChannel
  public let currentVersion: String
  /// The newest version a check found; nil when none was made or it found nothing newer.
  public let latestVersion: String?
  public let updateAvailable: Bool
  /// Set when updating is not possible; then no check ran.
  public let reason: UpdateUnavailableReason?

  public init(
    channel: InstallChannel, currentVersion: String = Version.current,
    latestVersion: String? = nil, updateAvailable: Bool = false,
    reason: UpdateUnavailableReason? = nil
  ) {
    self.channel = channel
    self.currentVersion = currentVersion
    self.latestVersion = latestVersion
    self.updateAvailable = updateAvailable
    self.reason = reason
  }
}

/// The app's updater (Sparkle in production).
public protocol UpdateControlling: Sendable {
  /// Whether updating is possible here and what is known, without a check or a window.
  func status() async -> UpdateStatus
  /// Looks for an update without any UI.
  /// - Throws: `.serverUnreachable` when the check fails or takes too long.
  func probe() async throws(NtfyError) -> UpdateStatus
  /// Starts the interactive flow (Sparkle's own windows) and returns at once.
  func startInteractive() async -> UpdateStatus
}

/// Whether updating is possible, from what the install and its signature say.
public struct UpdateEligibility: Sendable, Hashable {
  public let channel: InstallChannel
  public let signing: SigningInfo
  public let pin: TeamPin.Verdict
  /// Nil when updating is possible.
  public let reason: UpdateUnavailableReason?

  /// The Team ID to record now (first Developer-ID-signed run), if any.
  public var teamToRecord: String? {
    if case .record(let team) = pin { return team }
    return nil
  }

  public static func evaluate(
    channel: InstallChannel, disabled: Bool, signing: SigningInfo, recordedTeam: String?
  ) -> UpdateEligibility {
    let pin = TeamPin.evaluate(
      recorded: recordedTeam, current: signing.developerID ? signing.teamID : nil)
    let reason: UpdateUnavailableReason? =
      if channel == .homebrew {
        .homebrew
      } else if disabled {
        .disabled
      } else if pin == .unsigned {
        .unsigned
      } else if pin == .mismatch {
        .teamMismatch
      } else {
        nil
      }
    return UpdateEligibility(channel: channel, signing: signing, pin: pin, reason: reason)
  }
}
