import Foundation

/// The notification pause as the config file stores it (`pausedUntil`).
public enum PauseWindow {
  /// "Until further notice" is stored as this far-future date.
  public static let indefinite = Date(timeIntervalSince1970: 4_102_444_800)  // 2100-01-01T00:00:00Z

  public static func isIndefinite(_ date: Date) -> Bool { date >= indefinite }
}
