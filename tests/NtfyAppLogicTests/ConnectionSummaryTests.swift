import Foundation
import NtfyAppLogic
import NtfyCore
import Testing

@Suite struct ConnectionSummaryTests {
  @Test func everyStatusMapsToADisplayState() {
    let until = Date(timeIntervalSince1970: 100)
    #expect(ConnectionSummary(.stopped) == .connecting)
    #expect(ConnectionSummary(.connecting) == .connecting)
    #expect(ConnectionSummary(.connected) == .connected)
    #expect(
      ConnectionSummary(.backingOff(until: until, attempt: 2))
        == .retrying(until: until, attempt: 2)
    )
    #expect(ConnectionSummary(.offline) == .offline)
    #expect(ConnectionSummary(.paused) == .sleeping)
    #expect(
      ConnectionSummary(.halted(.unauthorized))
        == .needsAttention(reason: "The server rejected the access token"))
  }

  @Test func onlyUserFixableStatesSendTheUserToSettings() {
    let needing: [ConnectionSummary] = [.notConfigured, .needsAttention(reason: "x")]
    let others: [ConnectionSummary] = [
      .connecting, .connected, .retrying(until: .now, attempt: 1), .offline, .sleeping,
    ]
    #expect(needing.allSatisfy { $0.needsSettings })
    #expect(others.allSatisfy { !$0.needsSettings })
  }

  @Test func messageRowsFallBackToTheBodyForATitle() {
    let time = Date(timeIntervalSince1970: 0)
    let titled = MessageRow(
      StoredMessage(message: NtfyMessage(id: "1", topic: "t", time: time, title: " Hi ", body: "b"))
    )
    let untitled = MessageRow(
      StoredMessage(
        message: NtfyMessage(id: "2", topic: "t", time: time, body: "first line\nsecond")))
    let empty = MessageRow(
      StoredMessage(message: NtfyMessage(id: "3", topic: "t", time: time, body: "")))
    #expect(titled.title == "Hi")
    #expect(untitled.title == "first line")
    #expect(empty.title == "t")
  }
}
