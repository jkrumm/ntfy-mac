import Foundation

/// Signals when the config file changes on disk.
///
/// Watches the file's *directory*, because an atomic replace (temp file + rename) swaps the inode
/// and a watch on the file itself would go blind. Events are debounced, and a signal is only sent
/// when the file's identity (inode, size, modification time) actually changed, so the temp file
/// of a writer and unrelated files in the directory stay quiet. An in-place edit that keeps the
/// inode is seen only when the directory also gets an event; atomic writers always do.
///
/// The directory is created (mode 700) if missing, so a first `setup` is noticed.
public struct ConfigWatcher: Sendable {
  private let file: URL
  private let debounce: Duration

  public init(file: URL = FileConfigStore.defaultURL, debounce: Duration = .milliseconds(150)) {
    self.file = file
    self.debounce = debounce
  }

  /// One signal per settled change. Each call starts its own watch; it stops, and releases its
  /// file descriptor, when the stream terminates (consumer cancelled or stopped iterating).
  /// Finishes immediately if the directory cannot be watched.
  public func changes() -> AsyncStream<Void> {
    AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
      guard let watch = DirectoryWatch(file: file, debounce: debounce, continuation: continuation)
      else {
        continuation.finish()
        return
      }
      continuation.onTermination = { _ in watch.stop() }
    }
  }
}

/// Owns the descriptor and the dispatch source. All mutable state is touched only on `queue`.
private final class DirectoryWatch: @unchecked Sendable {
  private struct Fingerprint: Equatable {
    let inode: UInt64
    let size: Int64
    let seconds: Int
    let nanoseconds: Int
  }

  private let file: URL
  private let debounce: DispatchTimeInterval
  private let continuation: AsyncStream<Void>.Continuation
  private let queue = DispatchQueue(label: "com.jkrumm.ntfy-mac.config-watcher", qos: .utility)
  private var source: (any DispatchSourceFileSystemObject)?
  private var pending: DispatchWorkItem?
  private var last: Fingerprint?

  init?(file: URL, debounce: Duration, continuation: AsyncStream<Void>.Continuation) {
    let directory = file.deletingLastPathComponent()
    try? FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let descriptor = open(directory.path, O_EVTONLY)
    guard descriptor >= 0 else { return nil }

    self.file = file
    self.debounce = .milliseconds(
      Int(
        debounce.components.seconds * 1000
          + debounce.components.attoseconds / 1_000_000_000_000_000))
    self.continuation = continuation
    self.last = Self.fingerprint(of: file)

    let source = DispatchSource.makeFileSystemObjectSource(
      fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .extend, .link],
      queue: queue)
    source.setEventHandler { [weak self] in self?.directoryChanged() }
    source.setCancelHandler { close(descriptor) }
    self.source = source
    source.resume()
  }

  func stop() {
    queue.async { [self] in
      pending?.cancel()
      pending = nil
      source?.cancel()
      source = nil
    }
  }

  private func directoryChanged() {
    pending?.cancel()
    let item = DispatchWorkItem { [weak self] in self?.settled() }
    pending = item
    queue.asyncAfter(deadline: .now() + debounce, execute: item)
  }

  private func settled() {
    let current = Self.fingerprint(of: file)
    guard current != last else { return }
    last = current
    continuation.yield()
  }

  private static func fingerprint(of url: URL) -> Fingerprint? {
    var info = stat()
    guard stat(url.path, &info) == 0 else { return nil }
    return Fingerprint(
      inode: UInt64(info.st_ino), size: Int64(info.st_size),
      seconds: info.st_mtimespec.tv_sec, nanoseconds: info.st_mtimespec.tv_nsec)
  }
}
