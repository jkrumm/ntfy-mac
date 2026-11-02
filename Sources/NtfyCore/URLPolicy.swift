import Foundation

/// Which URLs the app may open or fetch on a message's behalf.
public enum URLPolicy {
  private static let openableSchemes: Set<String> = ["http", "https", "mailto"]
  private static let webSchemes: Set<String> = ["http", "https"]

  /// The URL when it may be opened (http, https, mailto); nil for every other scheme,
  /// and for http(s) without a host.
  public static func openable(_ url: URL) -> URL? {
    allowed(url, schemes: openableSchemes)
  }

  /// The URL when it may be fetched as an image or icon (http, https only).
  public static func imageURL(_ url: URL) -> URL? {
    allowed(url, schemes: webSchemes)
  }

  private static func allowed(_ url: URL, schemes: Set<String>) -> URL? {
    guard let scheme = url.scheme?.lowercased(), schemes.contains(scheme) else { return nil }
    if webSchemes.contains(scheme), (url.host() ?? "").isEmpty { return nil }
    return url
  }
}
