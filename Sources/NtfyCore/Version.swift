/// Version information for ntfy-mac.
public enum Version {
  /// The current version string.
  public static let current = "2.0.0-dev"

  /// Formats the user-facing version line.
  public static func banner(name: String = "ntfy-mac") -> String {
    "\(name) \(current)"
  }
}
