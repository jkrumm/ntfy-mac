import Foundation
import NtfyCore
import Security

/// Stores the access token as a generic password item in the login Keychain.
public struct KeychainSecretStore: SecretStore {
  private let service: String
  private let account: String

  public init(service: String = Log.subsystem, account: String = "token") {
    self.service = service
    self.account = account
  }

  private var identity: [CFString: Any] {
    [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
  }

  public func token() async throws(NtfyError) -> String? {
    var query = identity
    query[kSecReturnData] = true
    query[kSecMatchLimit] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else { throw Self.error(status) }
    return String(data: data, encoding: .utf8)
  }

  public func setToken(_ token: String) async throws(NtfyError) {
    let data = Data(token.utf8)
    let update = SecItemUpdate(identity as CFDictionary, [kSecValueData: data] as CFDictionary)
    if update == errSecSuccess { return }
    guard update == errSecItemNotFound else { throw Self.error(update) }
    var attributes = identity
    attributes[kSecValueData] = data
    let add = SecItemAdd(attributes as CFDictionary, nil)
    guard add == errSecSuccess else { throw Self.error(add) }
  }

  public func deleteToken() async throws(NtfyError) {
    let status = SecItemDelete(identity as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(status) }
  }

  private static func error(_ status: OSStatus) -> NtfyError {
    status == errSecAuthFailed || status == errSecInteractionNotAllowed
      ? .permissionDenied : .storage("keychain status \(status)")
  }
}
