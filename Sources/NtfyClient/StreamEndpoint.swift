import Foundation
import NtfyCore

/// Builds the subscription URL for a set of topics.
public enum StreamEndpoint {
  /// ntfy topic names: letters, digits, `_` and `-`, at most 64 characters (docs.ntfy.sh/publish).
  private static func isValid(topic: String) -> Bool {
    (1...64).contains(topic.utf8.count)
      && topic.utf8.allSatisfy { byte in
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
          || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
          || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
          || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_")
      }
  }

  public static func url(base: URL, topics: [String], since: String?) throws(NtfyError) -> URL {
    guard !topics.isEmpty else { throw .invalidResponse("no topics to subscribe to") }
    if let bad = topics.first(where: { !isValid(topic: $0) }) {
      throw .invalidTopic(bad)
    }
    guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false),
      let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
      components.host?.isEmpty == false
    else {
      throw .invalidResponse("server URL must be http(s) with a host")
    }
    var path = components.percentEncodedPath
    if !path.hasSuffix("/") { path += "/" }
    components.percentEncodedPath = path + topics.joined(separator: ",") + "/json"
    components.fragment = nil
    components.percentEncodedQuery = nil
    if let since {
      components.queryItems = [URLQueryItem(name: "since", value: since)]
    }
    guard let url = components.url else { throw .invalidResponse("malformed server URL") }
    return url
  }
}
