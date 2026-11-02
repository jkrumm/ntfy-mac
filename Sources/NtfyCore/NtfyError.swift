/// Every failure the ports can report. Exit-code mapping lives in the CLI only.
public enum NtfyError: Error, Sendable, Hashable {
  /// The server rejected the credentials (HTTP 401/403).
  case unauthorized
  /// The server could not be reached.
  case serverUnreachable
  /// The menu bar app is not running or not reachable over its socket.
  case appUnavailable
  /// A system permission (notifications, Keychain) is missing.
  case permissionDenied
  /// The server or a peer sent something we cannot interpret.
  case invalidResponse(String)
  /// Reading or writing persisted state failed.
  case storage(String)
}
