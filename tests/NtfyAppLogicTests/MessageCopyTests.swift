import Foundation
import NtfyAppLogic
import NtfyCore
import Testing

/// The one Copy: title, a blank line, body; a part that is empty is left out.
@Suite struct MessageCopyTests {
  private func stored(title: String?, body: String) -> StoredMessage {
    StoredMessage(
      message: NtfyMessage(
        id: "m", topic: "alerts", time: .distantPast, title: title, body: body))
  }

  private func texts(title: String?, body: String) -> (row: String, detail: String) {
    let message = stored(title: title, body: body)
    return (MessageRow(message).copyText, MessageDetail(message, now: .distantPast).copyText)
  }

  @Test func titleAndBodyAreCopiedTogetherWithABlankLine() {
    let copied = texts(title: "Disk full", body: "/var is at 99%")
    #expect(copied.row == "Disk full\n\n/var is at 99%")
    #expect(copied.detail == copied.row)
  }

  @Test func aBodyOnlyMessageCopiesJustTheBodyWithoutRepeatingItsFirstLine() {
    let copied = texts(title: nil, body: "headline\nsecond line")
    #expect(copied.row == "headline\nsecond line")
    #expect(copied.detail == copied.row)
    #expect(texts(title: "  ", body: "only").row == "only")
  }

  @Test func aTitleOnlyMessageCopiesJustTheTitle() {
    let copied = texts(title: "Backup done", body: "")
    #expect(copied.row == "Backup done")
    #expect(copied.detail == "Backup done")
  }

  @Test func aMessageWithNeitherCopiesNothing() {
    #expect(texts(title: nil, body: "").row.isEmpty)
    #expect(texts(title: nil, body: "  \n ").detail.isEmpty)
  }
}
