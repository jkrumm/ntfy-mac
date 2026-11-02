import Darwin

/// What the accept loop does with a failed `accept`.
enum AcceptFailure: Equatable {
  /// Try again at once: the call was interrupted or the peer already left.
  case retry
  /// The listener is closed; the loop ends.
  case stop
  /// A resource problem (out of descriptors, memory): wait before trying again.
  case backOff

  static func classify(_ code: Int32) -> AcceptFailure {
    switch code {
    case EINTR, ECONNABORTED, EAGAIN: .retry
    case EBADF, EINVAL, ENOTSOCK: .stop
    default: .backOff
    }
  }
}

/// 50 ms, doubling to 1 s while `accept` keeps failing; `reset` after a success.
struct AcceptBackoff {
  static let initial: Duration = .milliseconds(50)
  static let ceiling: Duration = .seconds(1)

  private var current = AcceptBackoff.initial
  private(set) var failures = 0

  /// The first failure of a burst, the only one that is logged.
  var isFirstFailure: Bool { failures == 0 }

  mutating func next() -> Duration {
    defer {
      failures += 1
      current = min(current * 2, Self.ceiling)
    }
    return current
  }

  mutating func reset() {
    current = Self.initial
    failures = 0
  }
}

/// Which file a socket path pointed to when the server bound it, so only that one is removed.
struct SocketIdentity: Equatable, Sendable {
  let device: dev_t
  let inode: ino_t

  /// Nil when nothing socket-like exists at `path`.
  init?(path: String) {
    var info = stat()
    guard lstat(path, &info) == 0, info.st_mode & S_IFMT == S_IFSOCK else { return nil }
    device = info.st_dev
    inode = info.st_ino
  }
}
