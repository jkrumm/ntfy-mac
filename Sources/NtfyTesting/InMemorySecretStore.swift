import NtfyCore

public actor InMemorySecretStore: SecretStore {
  private var stored: String?

  public init(token: String? = nil) {
    stored = token
  }

  public func token() -> String? { stored }
  public func setToken(_ token: String) { stored = token }
  public func deleteToken() { stored = nil }
}
