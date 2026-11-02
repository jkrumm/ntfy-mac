import Foundation

/// Classifies a URL host or a numeric address as private or special-purpose by its text alone;
/// never resolves names (see `HostSafety` for that).
public enum NetworkHost {
  public static func isPrivate(_ rawHost: String) -> Bool {
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

  /// Private, loopback, link-local, shared, documentation, benchmarking, multicast and reserved
  /// IPv4 space.
  private static func isPrivateIPv4(_ address: UInt32) -> Bool {
    let blocks: [(base: UInt32, bits: UInt32)] = [
      (0x0000_0000, 8),  // 0.0.0.0/8 "this network"
      (0x0A00_0000, 8),  // 10/8
      (0x6440_0000, 10),  // 100.64/10 carrier-grade NAT
      (0x7F00_0000, 8),  // 127/8
      (0xA9FE_0000, 16),  // 169.254/16
      (0xAC10_0000, 12),  // 172.16/12
      (0xC000_0000, 24),  // 192.0.0.0/24 IETF protocol assignments
      (0xC000_0200, 24),  // 192.0.2/24 documentation
      (0xC0A8_0000, 16),  // 192.168/16
      (0xC612_0000, 15),  // 198.18/15 benchmarking
      (0xC633_6400, 24),  // 198.51.100/24 documentation
      (0xCB00_7100, 24),  // 203.0.113/24 documentation
      (0xE000_0000, 3),  // 224/4 multicast and 240/4 reserved, including broadcast
    ]
    return blocks.contains { block in
      let mask = block.bits == 0 ? 0 : UInt32.max << (32 - block.bits)
      return address & mask == block.base
    }
  }

  private static func isPrivateIPv6(_ host: String) -> Bool {
    var address = in6_addr()
    guard inet_pton(AF_INET6, host, &address) == 1 else { return true }
    let bytes = withUnsafeBytes(of: &address) { Array($0) }
    let embedded = bytes[12...].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    // ::, ::1 and the deprecated IPv4-compatible form.
    if bytes[..<12].allSatisfy({ $0 == 0 }) { return true }
    // IPv4-mapped (::ffff:a.b.c.d): the embedded address decides.
    if bytes[..<10].allSatisfy({ $0 == 0 }), bytes[10] == 0xFF, bytes[11] == 0xFF {
      return isPrivateIPv4(embedded)
    }
    // NAT64 (64:ff9b::/96): the embedded address decides.
    if bytes[..<4] == [0x00, 0x64, 0xFF, 0x9B], bytes[4..<12].allSatisfy({ $0 == 0 }) {
      return isPrivateIPv4(embedded)
    }
    if bytes[0] == 0xFF { return true }
    if bytes[0] & 0xFE == 0xFC { return true }
    if bytes[0] == 0xFE, bytes[1] & 0xC0 == 0x80 { return true }
    return bytes[..<4] == [0x20, 0x01, 0x0D, 0xB8]
  }

  private static func isPrivateName(_ host: String) -> Bool {
    guard host.contains(".") else { return true }
    return host.hasSuffix(".local") || host.hasSuffix(".internal") || host.hasSuffix(".localhost")
  }
}
