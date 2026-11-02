import Foundation
import NtfyCore
import Testing

@testable import NtfyClient

@Suite struct EventDecoderTests {
  private func decode(_ json: String) throws -> NtfyMessage? {
    try EventDecoder.decode(line: Data(json.utf8))
  }

  @Test func decodesMessageEvent() throws {
    let message = try #require(
      try decode(
        """
        {"id":"a1","time":1700000000,"event":"message","topic":"t","message":"hi",\
        "title":"T","priority":5,"tags":["x"],"click":"https://example.com/a"}
        """))
    #expect(message.id == "a1")
    #expect(message.body == "hi")
    #expect(message.title == "T")
    #expect(message.priority == .max)
    #expect(message.tags == ["x"])
    #expect(message.click == URL(string: "https://example.com/a"))
    #expect(message.time == Date(timeIntervalSince1970: 1_700_000_000))
  }

  @Test func absentOptionalFieldsDefault() throws {
    let message = try #require(
      try decode(#"{"id":"a","time":1,"event":"message","topic":"t","message":"m"}"#))
    #expect(message.tags.isEmpty)
    #expect(message.title == nil)
    #expect(message.click == nil)
    #expect(message.priority == .default)
  }

  @Test func absentMessageBodyIsEmpty() throws {
    let message = try #require(try decode(#"{"id":"a","time":1,"event":"message","topic":"t"}"#))
    #expect(message.body.isEmpty)
  }

  @Test func clampsOutOfRangePriority() throws {
    let wild = #"{"id":"a","time":1,"event":"message","topic":"t","priority":9}"#
    #expect(try decode(wild)?.priority == .max)
  }

  @Test func acceptsFractionalTime() throws {
    let message = try #require(
      try decode(#"{"id":"a","time":1700000000.5,"event":"message","topic":"t"}"#))
    #expect(message.time == Date(timeIntervalSince1970: 1_700_000_000.5))
  }

  @Test(arguments: [
    "keepalive", "open", "poll_request", "message_delete", "message_clear", "future",
  ])
  func ignoresNonMessageEvents(event: String) throws {
    #expect(try decode(#"{"id":"k","time":1,"event":"\#(event)","topic":"t"}"#) == nil)
  }

  @Test(arguments: [
    #"{"time":1,"event":"message","topic":"t"}"#,
    #"{"id":"a","event":"message","topic":"t"}"#,
    #"{"id":"a","time":1,"topic":"t"}"#,
    #"{"id":"a","time":1,"event":"message"}"#,
    "nope",
    "",
  ])
  func rejectsUndecodableLines(line: String) {
    #expect(throws: NtfyError.invalidResponse("undecodable stream line")) { try decode(line) }
  }
}

@Suite struct StreamEndpointTests {
  private func url(_ base: String, _ topics: [String], since: String? = nil) throws -> String {
    try StreamEndpoint.url(base: #require(URL(string: base)), topics: topics, since: since)
      .absoluteString
  }

  @Test func joinsTopicsAndSince() throws {
    #expect(
      try url("https://ntfy.example.com", ["a", "b"], since: "xyz")
        == "https://ntfy.example.com/a,b/json?since=xyz")
  }

  @Test func keepsBasePathWithAndWithoutTrailingSlash() throws {
    #expect(try url("https://example.com/ntfy/", ["a"]) == "https://example.com/ntfy/a/json")
    #expect(try url("https://example.com/ntfy", ["a"]) == "https://example.com/ntfy/a/json")
  }

  @Test func dropsBaseQueryAndFragment() throws {
    #expect(try url("https://example.com/?x=1#f", ["a"]) == "https://example.com/a/json")
  }

  @Test func percentEncodesTheCursor() throws {
    #expect(
      try url("https://example.com", ["a"], since: "a b&c").contains("since=a%20b&c") == false)
    #expect(try url("https://example.com", ["a"], since: "a b").contains("since=a%20b"))
  }

  @Test(arguments: ["", "a b", "a/b", "a,b", "über", "a?x", String(repeating: "a", count: 65)])
  func rejectsInvalidTopics(topic: String) {
    #expect(throws: NtfyError.invalidTopic(topic)) {
      try StreamEndpoint.url(base: URL(string: "https://example.com")!, topics: [topic], since: nil)
    }
  }

  @Test func acceptsTopicCharsetAndMaxLength() throws {
    let longest = String(repeating: "a", count: 64)
    #expect(try url("https://example.com", ["A-z_09", longest]).hasSuffix("/json"))
  }

  @Test func requiresTopics() {
    #expect(throws: NtfyError.self) {
      try StreamEndpoint.url(base: URL(string: "https://example.com")!, topics: [], since: nil)
    }
  }

  @Test(arguments: ["ftp://example.com", "example.com", "file:///tmp"])
  func requiresHttpBaseWithHost(base: String) throws {
    #expect(throws: NtfyError.self) {
      try StreamEndpoint.url(base: #require(URL(string: base)), topics: ["a"], since: nil)
    }
  }
}
