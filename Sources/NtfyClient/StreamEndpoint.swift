import Foundation
import NtfyCore

/// Builds the subscription URL for a set of topics.
public enum StreamEndpoint {
  public static func url(base: URL, topics: [String], since: String?) -> URL? {
    guard !topics.isEmpty else { return nil }
    var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
    let basePath =
      components?.path.hasSuffix("/") == true
      ? components?.path ?? "" : (components?.path ?? "") + "/"
    components?.path = basePath + topics.joined(separator: ",") + "/json"
    components?.queryItems = since.map { [URLQueryItem(name: "since", value: $0)] }
    return components?.url
  }
}
