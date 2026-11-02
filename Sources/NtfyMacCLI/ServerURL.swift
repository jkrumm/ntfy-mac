import Foundation

/// A server address as the user types it.
enum ServerURL {
  /// `ntfy.example.com` becomes `https://ntfy.example.com`; one trailing slash goes. Only http
  /// and https servers with a host are accepted.
  static func parse(_ input: String) throws -> URL {
    var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { throw CLIFailure.usage("The server URL is empty.") }
    if let separator = text.range(of: "://") {
      let scheme = text[..<separator.lowerBound].lowercased()
      guard scheme == "http" || scheme == "https" else {
        throw CLIFailure.usage("The server URL must be http or https (got \(scheme):).")
      }
    } else {
      text = "https://" + text
    }
    guard let parsed = URL(string: text), let host = parsed.host(), !host.isEmpty else {
      throw CLIFailure.usage("Invalid server URL: \(input)")
    }
    var address = parsed.absoluteString
    while address.hasSuffix("/") { address.removeLast() }
    return URL(string: address) ?? parsed
  }
}
