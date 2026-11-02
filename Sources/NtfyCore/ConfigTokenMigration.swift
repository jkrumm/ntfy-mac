import Foundation

/// What a migration run found and did.
public enum TokenMigrationOutcome: Sendable, Hashable {
  /// The plaintext token moved into the secret store and left the file.
  case migrated
  /// The secret store already holds a token (it wins); any plaintext copy was scrubbed.
  case alreadyMigrated
  /// No token anywhere.
  case nothingToMigrate
}

/// Moves the 1.x plaintext token from the config file into the secret store.
///
/// The file is only touched after the secret store returned the same token on read-back, so a
/// failing store never costs the only copy. Running it again is a no-op.
public struct ConfigTokenMigration: Sendable {
  private let config: any ConfigStore
  private let secrets: any SecretStore

  public init(config: any ConfigStore, secrets: any SecretStore) {
    self.config = config
    self.secrets = secrets
  }

  public func run() async throws(NtfyError) -> TokenMigrationOutcome {
    let existing = try await secrets.token()
    let hasExisting = existing.map { !$0.isEmpty } ?? false
    guard
      let plaintext = try await config.load().token?.trimmingCharacters(
        in: .whitespacesAndNewlines),
      !plaintext.isEmpty
    else { return hasExisting ? .alreadyMigrated : .nothingToMigrate }

    if hasExisting {
      try await config.update { stored in
        if stored.token?.trimmingCharacters(in: .whitespacesAndNewlines) == plaintext {
          stored.token = nil
        }
      }
      return .alreadyMigrated
    }
    try await secrets.setToken(plaintext)
    guard try await secrets.token() == plaintext else {
      throw .storage("secret store did not return the migrated token; config left untouched")
    }
    // Only the token the store now holds may go; a token a concurrent writer put there stays.
    try await config.update { stored in
      if stored.token?.trimmingCharacters(in: .whitespacesAndNewlines) == plaintext {
        stored.token = nil
      }
    }
    return .migrated
  }
}
