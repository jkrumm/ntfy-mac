import Foundation
import NtfyAppLogic
import NtfyCore
import Testing

@Suite struct HistoryRowPreviewTests {
  private func row(title: String?, body: String, click: String? = nil) -> MessageRow {
    MessageRow(
      StoredMessage(
        message: NtfyMessage(
          id: "m", topic: "alerts", time: .distantPast, title: title, body: body,
          click: click.flatMap(URL.init(string:)))))
  }

  @Test func aTitledMessagePreviewsItsBody() {
    let titled = row(title: "Disk full", body: "line one\nline two")
    #expect(titled.hasTitle)
    #expect(titled.preview == "line one\nline two")
  }

  @Test func withoutATitleThePreviewSkipsTheFirstLineThatServesAsTitle() {
    let untitled = row(title: nil, body: "headline\n\nsecond\nthird")
    #expect(!untitled.hasTitle)
    #expect(untitled.title == "headline")
    #expect(untitled.preview == "second third")
    #expect(row(title: "  ", body: "only line").preview.isEmpty)
  }

  @Test func onlyOpenableClickURLsSurvive() {
    #expect(row(title: nil, body: "x", click: "https://example.com").clickURL != nil)
    #expect(row(title: nil, body: "x", click: "file:///etc/passwd").clickURL == nil)
  }
}
