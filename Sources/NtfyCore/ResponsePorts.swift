import Foundation

/// Opens a link in the user's default handler.
public protocol LinkOpening: Sendable {
  /// `false` when nothing could open the URL.
  func open(_ url: URL) async -> Bool
}

/// Brings the history entry of a message to the front.
public protocol HistoryPresenting: Sendable {
  func show(topic: String, id: String) async
}

/// Asks the user before a risky action runs.
public protocol ActionConfirming: Sendable {
  /// `reason` says why it is risky, `label` is the button the user pressed. `false` means no.
  func confirm(_ reason: String, action label: String) async -> Bool
}

/// Sends the request behind an `http` action button.
///
/// The caller has already run `ActionPolicy` (and asked for confirmation where it demanded
/// one); the runner only enforces transport limits.
public protocol HTTPActionRunning: Sendable {
  func run(_ call: HTTPCall) async throws(NtfyError)
}

/// Downloads the image of a notification so the poster can attach it.
public protocol ImageFetching: Sendable {
  /// A local file the poster may attach, or nil on any failure: an image is never required for
  /// delivery.
  func fetch(_ url: URL) async -> URL?
}

/// Turns a host name into the numeric addresses it points to.
///
/// Known residual: the answer can change between this check and the connection that follows
/// (DNS rebinding). Closing that would mean connecting to the checked address itself; the
/// check is a guard against a sender pointing a name at the local network, not a guarantee.
public protocol HostResolving: Sendable {
  /// Numeric addresses (IPv4 or IPv6 text), or nil when the lookup failed or took too long.
  func addresses(of host: String) async -> [String]?
}

/// The run-time half of the private-network check: what a name resolves to.
public enum HostSafety {
  /// `true` only when the host resolved and every address is public. A failed lookup counts as
  /// unsafe.
  public static func resolvesToPublicAddresses(
    _ host: String, using resolver: any HostResolving
  ) async -> Bool {
    guard let addresses = await resolver.addresses(of: host), !addresses.isEmpty else {
      return false
    }
    return !addresses.contains { NetworkHost.isPrivate($0) }
  }
}
