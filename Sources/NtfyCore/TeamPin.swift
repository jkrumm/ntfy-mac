/// Sparkle cannot pin a Team ID, so the app does: the Team ID of the first Developer-ID-signed
/// run is recorded, and a later run signed by another team does not update itself.
public enum TeamPin {
  public enum Verdict: Sendable, Hashable {
    /// First signed run: record this Team ID.
    case record(String)
    case matches
    case mismatch
    /// No Team ID (ad-hoc or development build): never recorded, never compared.
    case unsigned
  }

  /// - Parameters:
  ///   - recorded: The Team ID on file, nil before the first signed run.
  ///   - current: This build's Team ID, nil when it is not Developer-ID signed.
  public static func evaluate(recorded: String?, current: String?) -> Verdict {
    guard let current, !current.isEmpty else { return .unsigned }
    guard let recorded, !recorded.isEmpty else { return .record(current) }
    return recorded == current ? .matches : .mismatch
  }
}

/// Where the recorded Team ID lives. The app writes it; the CLI only reads.
public protocol TeamPinStoring: Sendable {
  func recorded() throws(NtfyError) -> String?
  func record(_ teamID: String) throws(NtfyError)
}
