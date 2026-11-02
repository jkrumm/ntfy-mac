import Foundation
import NtfyCore
import Security
import Testing

@testable import NtfyPlatform

/// Talks to the real login Keychain under a throwaway service name. Headless sessions (ssh, CI)
/// may have no unlocked keychain; the probe then skips instead of hanging or failing.
@Suite struct KeychainSecretStoreTests {
  private static func makeStore() -> KeychainSecretStore {
    KeychainSecretStore(service: "com.jkrumm.ntfy-mac.test.\(UUID().uuidString)")
  }

  private static var keychainAvailable: Bool {
    let probe = makeStore()
    return (try? probe.probe()) != nil
  }

  @Test(.enabled(if: keychainAvailable, "login keychain is not usable in this session"))
  func roundTripsOverwritesAndDeletes() async throws {
    let store = Self.makeStore()
    defer { Task { try? await store.deleteToken() } }
    #expect(try await store.token() == nil)
    try await store.setToken("one")
    #expect(try await store.token() == "one")
    try await store.setToken("two")
    #expect(try await store.token() == "two")
    try await store.deleteToken()
    #expect(try await store.token() == nil)
    try await store.deleteToken()
  }

  @Test(.enabled(if: keychainAvailable, "login keychain is not usable in this session"))
  func nonUTF8DataIsAStorageError() async throws {
    let store = Self.makeStore()
    defer { Task { try? await store.deleteToken() } }
    try store.plant(Data([0xFF, 0xFE, 0xFD]))
    await #expect(throws: NtfyError.storage("keychain item is not valid UTF-8")) {
      try await store.token()
    }
  }
}

extension KeychainSecretStore {
  fileprivate var raw: [CFString: Any] {
    [kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account]
  }

  /// Writes and removes an item with the real API; throws when the keychain is unusable.
  fileprivate func probe() throws {
    try plant(Data("probe".utf8))
    SecItemDelete(raw as CFDictionary)
  }

  /// Stores raw bytes, bypassing the String API.
  fileprivate func plant(_ data: Data) throws {
    var attributes = raw
    attributes[kSecValueData] = data
    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else {
      throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
    }
  }
}
