import Foundation
import NtfyCore
import Testing

@testable import NtfyClient

@Suite struct EventDecoderTests {
  @Test func decodesMessageEvent() throws {
    let line = Data(
      """
      {"id":"a1","time":1700000000,"event":"message","topic":"t","message":"hi",\
      "title":"T","priority":5,"tags":["x"]}
      """.utf8)
    let message = try #require(try EventDecoder.decode(line: line))
    #expect(message.id == "a1")
    #expect(message.body == "hi")
    #expect(message.title == "T")
    #expect(message.priority == .max)
    #expect(message.tags == ["x"])
    #expect(message.time == Date(timeIntervalSince1970: 1_700_000_000))
  }

  @Test func defaultsPriorityAndClampsOutOfRange() throws {
    let plain = Data(#"{"id":"a","time":1,"event":"message","topic":"t","message":"m"}"#.utf8)
    #expect(try EventDecoder.decode(line: plain)?.priority == .default)
    let wild = Data(
      #"{"id":"a","time":1,"event":"message","topic":"t","message":"m","priority":9}"#.utf8)
    #expect(try EventDecoder.decode(line: wild)?.priority == .max)
  }

  @Test func ignoresKeepaliveAndOpen() throws {
    let keepalive = Data(#"{"id":"k","time":1,"event":"keepalive","topic":"t"}"#.utf8)
    let open = Data(#"{"id":"o","time":1,"event":"open","topic":"t"}"#.utf8)
    #expect(try EventDecoder.decode(line: keepalive) == nil)
    #expect(try EventDecoder.decode(line: open) == nil)
  }

  @Test func rejectsGarbage() {
    #expect(throws: NtfyError.invalidResponse("undecodable stream line")) {
      try EventDecoder.decode(line: Data("nope".utf8))
    }
  }
}

@Suite struct StreamEndpointTests {
  @Test func joinsTopicsAndSince() throws {
    let base = try #require(URL(string: "https://ntfy.example.com"))
    let url = StreamEndpoint.url(base: base, topics: ["a", "b"], since: "xyz")
    #expect(url?.absoluteString == "https://ntfy.example.com/a,b/json?since=xyz")
  }

  @Test func keepsBasePathAndOmitsSince() throws {
    let base = try #require(URL(string: "https://example.com/ntfy/"))
    let url = StreamEndpoint.url(base: base, topics: ["a"], since: nil)
    #expect(url?.absoluteString == "https://example.com/ntfy/a/json")
  }

  @Test func needsAtLeastOneTopic() throws {
    let base = try #require(URL(string: "https://example.com"))
    #expect(StreamEndpoint.url(base: base, topics: [], since: nil) == nil)
  }
}
