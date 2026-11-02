import Foundation
import Testing

@testable import NtfyCore

@Suite struct URLPolicyTests {
  @Test(arguments: [
    "http://example.com", "https://example.com/a?b=1", "HTTPS://EXAMPLE.COM", "HtTp://example.com",
    "mailto:a@example.com", "MAILTO:a@example.com",
  ])
  func openableSchemes(raw: String) throws {
    let url = try #require(URL(string: raw))
    #expect(URLPolicy.openable(url) == url)
  }

  @Test(arguments: [
    "javascript:alert(1)", "JavaScript:alert(1)", "file:///etc/passwd", "data:text/html,x",
    "tel:+4912345", "ssh://host", "myapp://open", "ftp://example.com", "http://", "https:///path",
    "relative/path",
  ])
  func rejectedURLs(raw: String) {
    let url = URL(string: raw)
    #expect(url.flatMap(URLPolicy.openable) == nil)
  }

  @Test func imagesAreWebOnly() throws {
    #expect(URLPolicy.imageURL(try #require(URL(string: "https://e.com/a.png"))) != nil)
    #expect(URLPolicy.imageURL(try #require(URL(string: "HTTP://e.com/a.png"))) != nil)
    #expect(URLPolicy.imageURL(try #require(URL(string: "mailto:a@e.com"))) == nil)
    #expect(URLPolicy.imageURL(try #require(URL(string: "file:///tmp/a.png"))) == nil)
  }
}
