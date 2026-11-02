import Foundation

/// Why a server address typed by the user cannot be used.
public enum ServerAddressError: Error, Sendable, Hashable, CustomStringConvertible {
  case empty
  case unsupportedScheme(String)
  case invalid(String)

  public var description: String {
    switch self {
    case .empty: "The server URL is empty."
    case .unsupportedScheme(let scheme): "The server URL must be http or https (got \(scheme):)."
    case .invalid(let input): "Invalid server URL: \(input)"
    }
  }
}

/// A server address as the user types it, shared by the CLI and the app.
public enum ServerAddress {
  /// `ntfy.example.com` becomes `https://ntfy.example.com`; trailing slashes go. Only http and
  /// https servers with a host are accepted.
  public static func parse(_ input: String) throws(ServerAddressError) -> URL {
    var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw .empty }
    if let separator = text.range(of: "://") {
      let scheme = text[..<separator.lowerBound].lowercased()
      guard scheme == "http" || scheme == "https" else { throw .unsupportedScheme(scheme) }
    } else {
      text = "https://" + text
    }
    guard let parsed = URL(string: text), let host = parsed.host(), !host.isEmpty else {
      throw .invalid(input)
    }
    var address = parsed.absoluteString
    while address.hasSuffix("/") { address.removeLast() }
    return URL(string: address) ?? parsed
  }
}
