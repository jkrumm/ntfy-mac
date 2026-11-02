import Foundation

/// launchd, as far as removing a 1.x service needs it.
public protocol LaunchAgentManaging: Sendable {
  /// Whether the user domain has the service loaded.
  func isLoaded(label: String, uid: UInt32) async -> Bool
  /// Stops and unloads the service (`launchctl bootout gui/<uid>/<label>`).
  func bootout(label: String, uid: UInt32) async throws(NtfyError)
}

/// The Launch Services database, for registrations of the 1.x helper app.
public protocol LaunchServicesRegistering: Sendable {
  /// Every registered path of an app bundle named `ntfy-notify.app`.
  func registeredHelperPaths() async throws(NtfyError) -> [String]
  func unregister(path: String) async throws(NtfyError)
}

/// Looking at, and ending, the 1.x daemon when launchd does not own it.
public protocol LegacyProcessTerminating: Sendable {
  /// The real path of the process's executable; nil when no such process runs.
  func executablePath(of pid: Int32) -> String?
  /// Stops the process: SIGTERM, then SIGKILL if it lingers, but only while `pid` still runs
  /// `expectedPath` (the pid may have been reused). Throws when it survived.
  func terminate(_ pid: Int32, expectedPath: String) async throws(NtfyError)
}
