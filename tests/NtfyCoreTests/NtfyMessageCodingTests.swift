import Foundation
import Testing

@testable import NtfyCore

@Suite struct NtfyMessageCodingTests {
  @Test func rowsStoredBeforeTheNewFieldsStillDecode() throws {
    let old = """
      {"id":"a","topic":"t","time":700000000,"title":"T","body":"b","priority":4,\
      "tags":["x"],"click":"https://e.com","sequenceID":"s"}
      """
    let message = try JSONDecoder().decode(NtfyMessage.self, from: Data(old.utf8))
    #expect(message.id == "a")
    #expect(message.priority == .high)
    #expect(message.sequenceID == "s")
    #expect(message.icon == nil)
    #expect(message.attachment == nil)
    #expect(message.actions.isEmpty)
    #expect(message.expires == nil)
  }

  @Test func rowsStoredBeforeTheContentTypeExistedAreNotMarkdown() throws {
    let old = #"{"id":"a","topic":"t","time":1,"body":"title","priority":3}"#
    let message = try JSONDecoder().decode(NtfyMessage.self, from: Data(old.utf8))
    #expect(message.contentType == nil)
    #expect(!message.isMarkdown)
  }

  @Test(arguments: [
    ("text/markdown", true), ("text/markdown; charset=utf-8", true), (" Text/Markdown ", true),
    ("text/plain", false), ("text/markdownish", false), ("", false),
  ])
  func onlyTheMarkdownMediaTypeIsMarkdown(_ type: String, _ expected: Bool) {
    let message = NtfyMessage(
      id: "a", topic: "t", time: Date(timeIntervalSince1970: 1), body: "", contentType: type)
    #expect(message.isMarkdown == expected)
  }

  @Test func minimalRowDecodesWithDefaults() throws {
    let minimal = #"{"id":"a","topic":"t","time":1,"body":""}"#
    let message = try JSONDecoder().decode(NtfyMessage.self, from: Data(minimal.utf8))
    #expect(message.priority == .default)
    #expect(message.tags.isEmpty)
  }

  @Test func fullMessageRoundTrips() throws {
    let message = NtfyMessage(
      id: "a", topic: "t", time: Date(timeIntervalSince1970: 1_700_000_000), title: "T",
      body: "b", priority: .max, tags: ["x"], click: URL(string: "https://e.com"),
      sequenceID: "s", icon: URL(string: "https://e.com/i.png"),
      attachment: MessageAttachment(
        url: URL(string: "https://e.com/a.png")!, name: "a.png", mimeType: "image/png",
        size: 9, expires: Date(timeIntervalSince1970: 1_700_000_500)),
      actions: [
        MessageAction(
          id: "i", kind: .http, label: "Go", url: URL(string: "https://e.com/h"), method: "PUT",
          headers: ["X": "1"], body: "b", clear: true),
        MessageAction(kind: .unknown("future"), label: "F"),
      ],
      expires: Date(timeIntervalSince1970: 1_700_001_000), contentType: "text/markdown")
    let data = try JSONEncoder().encode(message)
    #expect(try JSONDecoder().decode(NtfyMessage.self, from: data) == message)
  }
}
