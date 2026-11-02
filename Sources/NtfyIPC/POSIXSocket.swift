import Darwin
import Dispatch
import Foundation

/// The blocking system calls behind the server and the client. Descriptors are non-blocking;
/// waiting is `poll` on a dispatch queue, so the cooperative pool is never held by a syscall.
enum POSIXSocket {
  private static let slice: Int32 = 100

  // MARK: Setup

  static func address(for path: String) throws(IPCError) -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw .pathTooLong }
    withUnsafeMutableBytes(of: &address.sun_path) { raw in
      for (index, byte) in bytes.enumerated() { raw[index] = UInt8(bitPattern: byte) }
    }
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    return address
  }

  /// A new non-blocking stream socket that does not raise SIGPIPE.
  static func makeSocket() throws(IPCError) -> Int32 {
    let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
    guard descriptor >= 0 else { throw .system("socket", errno) }
    do throws(IPCError) {
      try configure(descriptor)
    } catch {
      close(descriptor)
      throw error
    }
    return descriptor
  }

  static func configure(_ descriptor: Int32) throws(IPCError) {
    var enabled: Int32 = 1
    guard
      setsockopt(
        descriptor, SOL_SOCKET, SO_NOSIGPIPE, &enabled, socklen_t(MemoryLayout<Int32>.size))
        == 0
    else { throw .system("setsockopt", errno) }
    let flags = fcntl(descriptor, F_GETFL)
    guard flags >= 0, fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) == 0 else {
      throw .system("fcntl", errno)
    }
  }

  /// `connect` result: 0 on success, else errno.
  static func connect(_ descriptor: Int32, to path: String) throws(IPCError) -> Int32 {
    var address = try address(for: path)
    let result = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    return result == 0 ? 0 : errno
  }

  static func bind(_ descriptor: Int32, to path: String) throws(IPCError) {
    var address = try address(for: path)
    let result = withUnsafePointer(to: &address) { pointer in
      pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard result == 0 else { throw .system("bind", errno) }
  }

  /// Whether the peer runs as the same user as this process.
  static func peerIsCurrentUser(_ descriptor: Int32) -> Bool {
    var uid: uid_t = 0
    var gid: gid_t = 0
    return getpeereid(descriptor, &uid, &gid) == 0 && uid == geteuid()
  }

  // MARK: Waiting

  static func waitReadable(_ descriptor: Int32, milliseconds: Int32 = slice) async -> Bool {
    await wait(descriptor, events: Int16(POLLIN), milliseconds: milliseconds)
  }

  static func waitWritable(_ descriptor: Int32, milliseconds: Int32 = slice) async -> Bool {
    await wait(descriptor, events: Int16(POLLOUT), milliseconds: milliseconds)
  }

  private static func wait(_ descriptor: Int32, events: Int16, milliseconds: Int32) async -> Bool {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        var entry = pollfd(fd: descriptor, events: events, revents: 0)
        continuation.resume(returning: poll(&entry, 1, milliseconds) > 0)
      }
    }
  }

  // MARK: Frames

  /// Reads up to the first newline; the newline is not part of the result. Bytes after it are
  /// dropped: a connection carries one request and one response.
  static func readLine(_ descriptor: Int32, limit: Int, timeout: Duration) async throws(IPCError)
    -> Data
  {
    var buffer = Data()
    let deadline = ContinuousClock.now.advanced(by: timeout)
    var chunk = [UInt8](repeating: 0, count: 4096)
    while true {
      if let newline = buffer.firstIndex(of: 0x0A) {
        guard newline <= limit else { throw .frameTooLarge }
        return buffer.prefix(upTo: newline)
      }
      guard buffer.count <= limit else { throw .frameTooLarge }
      try checkpoint(deadline)
      guard await waitReadable(descriptor) else { continue }
      let count = read(descriptor, &chunk, chunk.count)
      if count > 0 {
        buffer.append(contentsOf: chunk[0..<count])
      } else if count == 0 {
        throw .connectionClosed
      } else if errno != EAGAIN, errno != EINTR {
        throw .system("read", errno)
      }
    }
  }

  static func writeAll(_ descriptor: Int32, _ data: Data, timeout: Duration) async throws(IPCError)
  {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    var offset = 0
    while offset < data.count {
      try checkpoint(deadline)
      guard await waitWritable(descriptor) else { continue }
      let written = data.withUnsafeBytes { raw in
        write(descriptor, raw.baseAddress.map { $0 + offset }, data.count - offset)
      }
      if written > 0 {
        offset += written
      } else if written < 0, errno != EAGAIN, errno != EINTR {
        throw .system("write", errno)
      }
    }
  }

  /// Reads and discards until the peer closes, `limit` bytes passed or `timeout` ran out. After
  /// an early reply this keeps the close from turning into a reset that eats the reply.
  static func drain(_ descriptor: Int32, limit: Int, timeout: Duration) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    var chunk = [UInt8](repeating: 0, count: 4096)
    var total = 0
    while total < limit, ContinuousClock.now < deadline, !Task.isCancelled {
      guard await waitReadable(descriptor) else { continue }
      let count = read(descriptor, &chunk, chunk.count)
      if count > 0 {
        total += count
      } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
        return
      }
    }
  }

  private static func checkpoint(_ deadline: ContinuousClock.Instant) throws(IPCError) {
    if Task.isCancelled { throw .cancelled }
    if ContinuousClock.now >= deadline { throw .timedOut }
  }
}
