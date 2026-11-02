import Foundation
import NtfyCore
import Synchronization

/// `HostResolving` over `getaddrinfo`, run off the calling task with a hard time limit. A lookup
/// that outlives the limit is abandoned (its thread finishes on its own) and counts as failed.
public struct SystemHostResolver: HostResolving {
  private let timeout: Duration

  public init(timeout: Duration = .seconds(3)) {
    self.timeout = timeout
  }

  public func addresses(of host: String) async -> [String]? {
    let limit = DispatchTimeInterval.milliseconds(
      Int(
        timeout.components.seconds * 1000 + timeout.components.attoseconds / 1_000_000_000_000_000)
    )
    return await withCheckedContinuation { continuation in
      let once = Once(continuation)
      DispatchQueue.global(qos: .utility).async { once.resume(Self.lookup(host)) }
      DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + limit) {
        once.resume(nil)
      }
    }
  }

  static func lookup(_ host: String) -> [String]? {
    var hints = addrinfo()
    hints.ai_family = AF_UNSPEC
    hints.ai_socktype = SOCK_STREAM
    var head: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, nil, &hints, &head) == 0, let first = head else { return nil }
    defer { freeaddrinfo(head) }
    var result: [String] = []
    var cursor: UnsafeMutablePointer<addrinfo>? = first
    while let entry = cursor {
      var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      if let address = entry.pointee.ai_addr,
        getnameinfo(
          address, entry.pointee.ai_addrlen, &buffer, socklen_t(buffer.count), nil, 0,
          NI_NUMERICHOST) == 0
      {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        let text = String(bytes: bytes, encoding: .utf8) ?? ""
        result.append(text.split(separator: "%").first.map(String.init) ?? text)
      }
      cursor = entry.pointee.ai_next
    }
    return result
  }
}

/// Resumes its continuation at most once, whichever of lookup and timer comes first.
private final class Once: Sendable {
  private let continuation: Mutex<CheckedContinuation<[String]?, Never>?>

  init(_ continuation: CheckedContinuation<[String]?, Never>) {
    self.continuation = Mutex(continuation)
  }

  func resume(_ value: [String]?) {
    let taken = continuation.withLock { state -> CheckedContinuation<[String]?, Never>? in
      defer { state = nil }
      return state
    }
    taken?.resume(returning: value)
  }
}
