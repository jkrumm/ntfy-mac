import Foundation
import NtfyCore
import Security

/// Stores the access token as a generic password item in the login Keychain.
public struct KeychainSecretStore: SecretStore {
  let service: String
  let account: String

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
    guard let token = String(data: data, encoding: .utf8) else {
      throw .storage("keychain item is not valid UTF-8")
    }
    return token
  }

  public func setToken(_ token: String) async throws(NtfyError) {
    let data = Data(token.utf8)
    if try update(data) { return }
    var attributes = identity
    attributes[kSecValueData] = data
    let add = SecItemAdd(attributes as CFDictionary, nil)
    if add == errSecSuccess { return }
    // Lost a race with another writer between the update and the add: update once more.
    guard add == errSecDuplicateItem, try update(data) else { throw Self.error(add) }
  }

  /// Returns false when no item exists yet.
  private func update(_ data: Data) throws(NtfyError) -> Bool {
    let status = SecItemUpdate(identity as CFDictionary, [kSecValueData: data] as CFDictionary)
    if status == errSecSuccess { return true }
    if status == errSecItemNotFound { return false }
    throw Self.error(status)
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
