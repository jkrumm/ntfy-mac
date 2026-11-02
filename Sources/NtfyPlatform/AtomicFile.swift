import Foundation
import NtfyCore

/// Reads and atomically replaces small files. Every write goes to a private temp file in the
/// same directory and is renamed over the target, so a reader sees the old or the new content,
/// never a mix, and the secret never exists with looser permissions than the final file.
enum AtomicFile {
  /// Nil when the file does not exist.
  static func read(_ url: URL) throws(NtfyError) -> Data? {
    do {
      return try Data(contentsOf: url)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
      return nil
    } catch let error as NSError
      where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT)
    {
      return nil
    } catch {
      throw .storage("cannot read \(url.lastPathComponent): \(error.localizedDescription)")
    }
  }

  static func write(_ data: Data, to url: URL) throws(NtfyError) {
    let directory = url.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700])
    } catch {
      throw .storage("cannot create \(directory.lastPathComponent): \(error.localizedDescription)")
    }
    let temp = directory.appendingPathComponent(
      ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
    if let failure = writeTemp(data, at: temp) ?? replace(url, with: temp) {
      unlink(temp.path)
      throw .storage("cannot write \(url.lastPathComponent): \(failure)")
    }
    flushDirectory(directory)
  }

  /// Creates `temp` (mode 600), writes and syncs it. Returns a failure description, or nil.
  private static func writeTemp(_ data: Data, at temp: URL) -> String? {
    let descriptor = open(temp.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
    guard descriptor >= 0 else { return "cannot create temp file: errno \(errno)" }
    var failure = writeAll(data, to: descriptor)
    if failure == nil, !flushToDisk(descriptor) { failure = "fsync failed: errno \(errno)" }
    if close(descriptor) != 0, failure == nil { failure = "close failed: errno \(errno)" }
    return failure
  }

  /// `fsync` only hands the data to the drive; on macOS `F_FULLFSYNC` also flushes the drive's
  /// cache, which is what survives a power loss. Falls back to `fsync` where unsupported.
  private static func flushToDisk(_ descriptor: Int32) -> Bool {
    fcntl(descriptor, F_FULLFSYNC) != -1 || fsync(descriptor) == 0
  }

  /// Best effort: persist the directory entry the rename just created.
  private static func flushDirectory(_ directory: URL) {
    let descriptor = open(directory.path, O_RDONLY)
    guard descriptor >= 0 else { return }
    _ = flushToDisk(descriptor)
    close(descriptor)
  }

  private static func writeAll(_ data: Data, to descriptor: Int32) -> String? {
    data.withUnsafeBytes { buffer -> String? in
      guard let base = buffer.baseAddress else { return nil }
      var offset = 0
      while offset < buffer.count {
        let count = Darwin.write(descriptor, base + offset, buffer.count - offset)
        if count < 0 && errno == EINTR { continue }
        if count <= 0 { return "write failed: errno \(errno)" }
        offset += count
      }
      return nil
    }
  }

  private static func replace(_ url: URL, with temp: URL) -> String? {
    rename(temp.path, url.path) == 0 ? nil : "rename failed: errno \(errno)"
  }
}
