import Foundation
import NtfyCore
import Security

/// The code signature of a bundle on disk, read with Security.framework. Anything it cannot read
/// (no bundle, unsigned, ad hoc) is `SigningInfo.unsigned`.
public struct BundleSigningInspector: SigningInspecting {
  /// Apple's requirement for a Developer ID Application certificate chain.
  static let developerIDRequirement =
    "anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] "
    + "and certificate leaf[field.1.2.840.113635.100.6.1.13]"

  private let bundle: URL?

  public init(bundle: URL?) { self.bundle = bundle }

  public func inspect() -> SigningInfo {
    guard let bundle else { return .unsigned }
    var code: SecStaticCode?
    guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess, let code
    else { return .unsigned }
    var information: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
    guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
      let values = information as? [String: Any]
    else { return .unsigned }
    let team = values[kSecCodeInfoTeamIdentifier as String] as? String
    let raw = (values[kSecCodeInfoFlags as String] as? UInt32) ?? 0
    let hardened = SecCodeSignatureFlags(rawValue: raw).contains(.runtime)
    return SigningInfo(
      teamID: team, hardenedRuntime: hardened, developerID: isDeveloperID(code))
  }

  private func isDeveloperID(_ code: SecStaticCode) -> Bool {
    var requirement: SecRequirement?
    guard
      SecRequirementCreateWithString(Self.developerIDRequirement as CFString, [], &requirement)
        == errSecSuccess,
      let requirement
    else { return false }
    return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
  }
}

/// The entitlements of the running process.
public struct ProcessEntitlements: EntitlementProbing {
  public init() {}

  public func holds(_ entitlement: Entitlement) -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    let value = SecTaskCopyValueForEntitlement(task, entitlement.rawValue as CFString, nil)
    return value as? Bool == true
  }
}
