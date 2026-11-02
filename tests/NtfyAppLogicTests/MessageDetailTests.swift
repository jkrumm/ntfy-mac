import Foundation
import NtfyAppLogic
import NtfyCore
import Testing

@Suite struct MessageDetailTests {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  private func detail(
    click: String? = nil, actions: [MessageAction] = [], attachment: MessageAttachment? = nil
  ) -> MessageDetail {
    let message = NtfyMessage(
      id: "m", topic: "alerts", time: now, body: "body", click: click.flatMap { URL(string: $0) },
      attachment: attachment, actions: actions)
    return MessageDetail(StoredMessage(message: message), now: now)
  }

  @Test(arguments: [
    "javascript:alert(1)", "file:///etc/passwd", "data:text/html,hi", "ftp://example.com/a",
    "https:///nohost",
  ])
  func unsafeClickAndActionURLsComeOutNil(url: String) {
    let action = MessageAction(kind: .view, label: "Open", url: URL(string: url))
    let result = detail(click: url, actions: [action])
    #expect(result.clickURL == nil)
    #expect(result.actions.first?.url == nil)
  }

  @Test(arguments: ["https://example.com/a", "http://example.com/a", "mailto:me@example.com"])
  func openableClickAndActionURLsSurvive(url: String) {
    let action = MessageAction(kind: .view, label: "Open", url: URL(string: url))
    let result = detail(click: url, actions: [action])
    #expect(result.clickURL?.absoluteString == url)
    #expect(result.actions.first?.url?.absoluteString == url)
  }

  @Test func anAttachmentIsExpiredExactlyAtItsExpiryTime() throws {
    func expired(after offset: TimeInterval) throws -> Bool {
      let attachment = MessageAttachment(
        url: URL(fileURLWithPath: "/f.pdf"), expires: now.addingTimeInterval(offset))
      return try #require(detail(attachment: attachment).attachment).isExpired
    }
    #expect(try expired(after: 1) == false)
    #expect(try expired(after: 0))
    #expect(try expired(after: -1))
  }

  @Test func anAttachmentWithoutExpiryNeverExpires() throws {
    let attachment = MessageAttachment(url: URL(fileURLWithPath: "/x"))
    #expect(try !#require(detail(attachment: attachment).attachment).isExpired)
  }
}
