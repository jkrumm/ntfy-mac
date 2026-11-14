import Foundation
import NtfyCore
import Synchronization

/// The single-instance lock: an exclusive, non-blocking `flock` on `app.instance.lock` in the app
/// support dir. It is its own file because `app.sock.lock` belongs to the socket server, which
/// the pipeline starts later and which tolerates a failed bind; this one is taken first thing and
/// held for the whole life of the process. The kernel drops it when the process dies, so a crash
/// never leaves a stale lock.
public struct FileInstanceLock: InstanceLocking {
  public static let fileName = "app.instance.lock"

  /// `<application support>/ntfy-mac/app.instance.lock`, next to the socket and the history.
  public static func defaultURL(applicationSupport: URL) -> URL {
    applicationSupport
      .appending(path: "ntfy-mac", directoryHint: .isDirectory)
      .appending(path: fileName, directoryHint: .notDirectory)
  }

  private let url: URL

  public init(url: URL) { self.url = url }

  public func acquire() throws(NtfyError) -> (any InstanceLease)? {
    let directory = url.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    } catch {
      throw .storage("cannot create \(directory.lastPathComponent): \(error.localizedDescription)")
    }
    let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
      throw .storage("cannot open \(url.lastPathComponent): errno \(errno)")
    }
    while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
      let code = errno
      if code == EINTR { continue }
      close(descriptor)
      if code == EWOULDBLOCK { return nil }
      throw .storage("cannot lock \(url.lastPathComponent): errno \(code)")
    }
    return Lease(descriptor: descriptor)
  }

  private final class Lease: InstanceLease {
    private let descriptor: Mutex<Int32?>

    init(descriptor: Int32) { self.descriptor = Mutex(descriptor) }

    func release() {
      // Closing the descriptor releases the lock.
      if let open = descriptor.withLock({ state in
        defer { state = nil }
        return state
      }) {
        close(open)
      }
    }

    deinit { release() }
  }
}
