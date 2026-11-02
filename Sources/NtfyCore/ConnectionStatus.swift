import Foundation

/// Where the stream connection stands. Published by the supervisor, driven by `ReconnectMachine`.
public enum ConnectionStatus: Sendable, Hashable {
  /// Not started, or stopped.
  case stopped
  case connecting
  case connected
  /// Waiting to retry; `attempt` counts consecutive failures (0 after a clean close).
  case backingOff(until: Date, attempt: Int)
  /// No network path; nothing is attempted until it returns.
  case offline
  /// The Mac is going to sleep; nothing runs until it wakes.
  case paused
  /// A failure retrying cannot fix. Stays until an explicit restart.
  case halted(NtfyError)
}
