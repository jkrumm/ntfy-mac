import Foundation
import NtfyCore

/// An advisory `flock` on a sidecar file, so two processes (the app and the CLI) never run a
/// read-modify-write of the same file at once. The lock lives on its own file, never on the data
/// file, because the data file is replaced by rename and a lock would stay with the old inode.
enum FileLock {
  /// Runs `body` while holding an exclusive lock on `lockFile`, creating it (mode 600) if needed.
  /// Blocks until the lock is free; critical sections are one small file write.
  static func withExclusive<T>(
    _ lockFile: URL, _ body: () throws(NtfyError) -> T
  ) throws(NtfyError) -> T {
    let directory = lockFile.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    } catch {
      throw .storage("cannot create \(directory.lastPathComponent): \(error.localizedDescription)")
    }
    let descriptor = open(lockFile.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else {
      throw .storage("cannot open \(lockFile.lastPathComponent): errno \(errno)")
    }
    defer { close(descriptor) }  // closing the descriptor releases the lock
    while flock(descriptor, LOCK_EX) != 0 {
      guard errno == EINTR else {
        throw .storage("cannot lock \(lockFile.lastPathComponent): errno \(errno)")
      }
    }
    return try body()
  }
}
