/// What a bundle's code signature says about it.
public struct SigningInfo: Sendable, Hashable {
  public let teamID: String?
  public let hardenedRuntime: Bool
  /// Signed by a Developer ID Application certificate (not ad hoc, not a development identity).
  public let developerID: Bool
  /// The restricted entitlements the signature carries (a Developer ID build with a provisioning profile).
  public let entitlements: Set<Entitlement>

  public init(
    teamID: String? = nil, hardenedRuntime: Bool = false, developerID: Bool = false,
    entitlements: Set<Entitlement> = []
  ) {
    self.teamID = teamID
    self.hardenedRuntime = hardenedRuntime
    self.developerID = developerID
    self.entitlements = entitlements
  }

  /// Ad hoc, unsigned or unreadable.
  public static let unsigned = SigningInfo()
}

/// Reads the code signature of the app bundle this process belongs to.
public protocol SigningInspecting: Sendable {
  func inspect() -> SigningInfo
}

/// Reads the entitlements this process runs with. Restricted ones (time-sensitive
/// notifications) need a provisioning profile, so a build may or may not carry them.
public protocol EntitlementProbing: Sendable {
  func holds(_ entitlement: Entitlement) -> Bool
}

public enum Entitlement: String, Sendable, Hashable, CaseIterable {
  case timeSensitiveNotifications = "com.apple.developer.usernotifications.time-sensitive"
}
