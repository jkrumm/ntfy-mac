import Foundation
import NtfyCore
import Testing

@testable import NtfyClient

@Suite struct EventDecoderTests {
  private func decode(_ json: String) throws -> StreamEvent? {
    try EventDecoder.decode(line: Data(json.utf8))
  }

  private func decodeMessage(_ json: String) throws -> NtfyMessage? {
    guard case .message(let message)? = try decode(json) else { return nil }
    return message
  }

  @Test func decodesMessageEvent() throws {
    let message = try #require(
      try decodeMessage(
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
      try decodeMessage(#"{"id":"a","time":1,"event":"message","topic":"t","message":"m"}"#))
    #expect(message.tags.isEmpty)
    #expect(message.title == nil)
    #expect(message.click == nil)
    #expect(message.priority == .default)
  }

  @Test func absentMessageBodyIsEmpty() throws {
    let message = try #require(
      try decodeMessage(#"{"id":"a","time":1,"event":"message","topic":"t"}"#))
    #expect(message.body.isEmpty)
  }

  @Test func clampsOutOfRangePriority() throws {
    let wild = #"{"id":"a","time":1,"event":"message","topic":"t","priority":9}"#
    #expect(try decodeMessage(wild)?.priority == .max)
  }

  @Test func acceptsFractionalTime() throws {
    let message = try #require(
      try decodeMessage(#"{"id":"a","time":1700000000.5,"event":"message","topic":"t"}"#))
    #expect(message.time == Date(timeIntervalSince1970: 1_700_000_000.5))
  }

  @Test func decodesSequenceID() throws {
    let line = #"{"id":"b","time":1,"event":"message","topic":"t","sequence_id":"job-7"}"#
    #expect(try decodeMessage(line)?.sequenceID == "job-7")
    #expect(
      try decodeMessage(#"{"id":"b","time":1,"event":"message","topic":"t"}"#)?.sequenceID == nil)
  }

  @Test func decodesControlEvents() throws {
    #expect(try decode(#"{"id":"o","time":1,"event":"open","topic":"t1,t2"}"#) == .open)
    #expect(try decode(#"{"id":"k","time":1,"event":"keepalive","topic":"t"}"#) == .keepalive)
    #expect(try decode(#"{"id":"p","time":1,"event":"poll_request","topic":"t"}"#) == .pollRequest)
  }

  @Test func decodesDeleteAndClear() throws {
    let delete = #"{"id":"d","time":1,"event":"message_delete","topic":"t","sequence_id":"s"}"#
    let clear = #"{"id":"c","time":1,"event":"message_clear","topic":"t","sequence_id":"s"}"#
    #expect(try decode(delete) == .messageDelete(topic: "t", sequenceID: "s"))
    #expect(try decode(clear) == .messageClear(topic: "t", sequenceID: "s"))
  }

  @Test(arguments: ["message_delete", "message_clear"])
  func deleteAndClearNeedASequenceID(event: String) {
    let line = #"{"id":"d","time":1,"event":"\#(event)","topic":"t"}"#
    #expect(throws: NtfyError.invalidResponse("\(event) without sequence_id")) { try decode(line) }
  }

  @Test func unknownEventTypesAreSkipped() throws {
    #expect(try decode(#"{"id":"k","time":1,"event":"future","topic":"t"}"#) == nil)
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

  @Test func addsPollFlag() throws {
    let base = try #require(URL(string: "https://example.com"))
    let url = try StreamEndpoint.url(base: base, topics: ["a"], since: "x", poll: true)
    #expect(url.absoluteString == "https://example.com/a/json?since=x&poll=1")
  }

  @Test(arguments: ["http://ntfy.example.com", "http://192.168.1.5:8080", "HTTP://example.com"])
  func refusesTokenOverPlainHttp(base: String) throws {
    let base = try #require(URL(string: base))
    #expect(throws: NtfyError.insecureServer) {
      try StreamEndpoint.url(base: base, topics: ["a"], since: nil, token: "tk")
    }
  }

  @Test(arguments: [
    "http://localhost:8080", "http://127.0.0.1", "http://[::1]:2586", "http://LOCALHOST",
  ])
  func allowsTokenOverLoopbackHttp(base: String) throws {
    let base = try #require(URL(string: base))
    _ = try StreamEndpoint.url(base: base, topics: ["a"], since: nil, token: "tk")
  }

  @Test func allowsTokenOverPlainHttpOnOptIn() throws {
    let base = try #require(URL(string: "http://ntfy.example.com"))
    _ = try StreamEndpoint.url(
      base: base, topics: ["a"], since: nil, token: "tk", allowInsecure: true)
  }

  @Test func allowsAnonymousPlainHttp() throws {
    let base = try #require(URL(string: "http://ntfy.example.com"))
    _ = try StreamEndpoint.url(base: base, topics: ["a"], since: nil)
  }

  @Test(arguments: ["ftp://example.com", "example.com", "file:///tmp"])
  func requiresHttpBaseWithHost(base: String) throws {
    #expect(throws: NtfyError.self) {
      try StreamEndpoint.url(base: #require(URL(string: base)), topics: ["a"], since: nil)
    }
  }
}
