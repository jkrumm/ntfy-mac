/// Proof that this process is the one running instance of the app. Releasing it, or the process
/// ending, lets the next copy start.
public protocol InstanceLease: Sendable {
  func release()
}

/// The per-user lock behind "one NtfyMac at a time", whichever copy of the bundle is started.
public protocol InstanceLocking: Sendable {
  /// A lease when no other instance holds the lock, `nil` when one does. Never blocks.
  func acquire() throws(NtfyError) -> (any InstanceLease)?
}
