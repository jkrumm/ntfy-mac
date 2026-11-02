/// Everything the IPC layer can fail with. The CLI maps these to `NtfyError`/exit codes.
public enum IPCError: Error, Sendable, Hashable {
  case unsupportedProtocolVersion(Int)
  case malformedFrame
  /// The socket path does not fit `sockaddr_un.sun_path`.
  case pathTooLong
  /// Nothing listens on the socket: it is missing or stale.
  case appNotRunning
  /// A live server already owns the socket.
  case alreadyRunning
  case timedOut
  case frameTooLarge
  /// The peer closed before a whole frame arrived.
  case connectionClosed
  case cancelled
  /// A system call failed.
  case system(String, Int32)
}
