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

  /// `poll` turns the live subscription into a one-shot read of the cache.
  public static func url(
    base: URL, topics: [String], since: String?, poll: Bool = false, token: String? = nil,
    allowInsecure: Bool = false
  ) throws(NtfyError) -> URL {
    guard !topics.isEmpty else { throw .invalidResponse("no topics to subscribe to") }
    if let bad = topics.first(where: { !isValid(topic: $0) }) {
      throw .invalidTopic(bad)
    }
    var query: [URLQueryItem] = []
    if let since { query.append(URLQueryItem(name: "since", value: since)) }
    if poll { query.append(URLQueryItem(name: "poll", value: "1")) }
    return try ServerEndpoint.url(
      base: base, path: topics.joined(separator: ",") + "/json", query: query, token: token,
      allowInsecure: allowInsecure)
  }
}
