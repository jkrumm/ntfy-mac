import Foundation

/// Classifies a URL host as private-network by its text alone; never resolves names.
enum NetworkHost {
  static func isPrivate(_ rawHost: String) -> Bool {
    var host = rawHost.lowercased()
    if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
    while host.hasSuffix(".") { host.removeLast() }
    if host.contains(":") { return isPrivateIPv6(host) }
    if let address = ipv4(host) { return isPrivateIPv4(address) }
    return isPrivateName(host)
  }

  /// `inet_aton` rules, so shorthand (`127.1`), decimal (`2130706433`) and hex hosts count as IPs.
  private static func ipv4(_ host: String) -> UInt32? {
    var address = in_addr()
    guard inet_aton(host, &address) == 1 else { return nil }
    return UInt32(bigEndian: address.s_addr)
  }

  private static func isPrivateIPv4(_ address: UInt32) -> Bool {
    let first = address >> 24
    let second = (address >> 16) & 0xFF
    switch first {
    case 0, 10, 127: return true
    case 100: return (64...127).contains(second)
    case 169: return second == 254
    case 172: return (16...31).contains(second)
    case 192: return second == 168
    default: return false
    }
  }

  private static func isPrivateIPv6(_ host: String) -> Bool {
    var address = in6_addr()
    guard inet_pton(AF_INET6, host, &address) == 1 else { return true }
    let bytes = withUnsafeBytes(of: &address) { Array($0) }
    if bytes.dropLast().allSatisfy({ $0 == 0 }), bytes[15] <= 1 { return true }
    if bytes[..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
      let mapped = bytes[12...].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
      return isPrivateIPv4(mapped)
    }
    if bytes[0] & 0xFE == 0xFC { return true }
    return bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80
  }

  private static func isPrivateName(_ host: String) -> Bool {
    guard host.contains(".") else { return true }
    return host.hasSuffix(".local") || host.hasSuffix(".internal") || host.hasSuffix(".localhost")
  }
}
