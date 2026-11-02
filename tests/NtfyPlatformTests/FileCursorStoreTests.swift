import Foundation
import NtfyCore
import Testing

@testable import NtfyPlatform

@Suite struct FileCursorStoreTests {
  @Test func missingFileMeansNoCursor() async throws {
    let dir = TempDirectory()
    #expect(try await FileCursorStore(url: dir.file("state.json")).load() == nil)
  }

  @Test(arguments: ["", "garbage", "[1]", #"{"lastMessageId":null}"#, #"{"lastMessageId":5}"#])
  func corruptOrEmptyCursorMeansNoCursor(content: String) async throws {
    let dir = TempDirectory()
    try dir.write(content, to: "state.json")
    #expect(try await FileCursorStore(url: dir.file("state.json")).load() == nil)
  }

  @Test func reads1xState() async throws {
    let dir = TempDirectory()
    try dir.write(
      #"{"seen":{"a":1},"lastMessageId":"msg-1","lastUpdateCheck":12345}"#, to: "state.json")
    #expect(try await FileCursorStore(url: dir.file("state.json")).load() == "msg-1")
  }

  @Test func savePreservesEveryOtherKey() async throws {
    let dir = TempDirectory()
    try dir.write(
      """
      {"seen":{"msg-1":1700000000000},"lastMessageId":"msg-1","lastUpdateCheck":12345,
       "reminders":[{"id":"r1","fireAt":1700000060000,"title":"T","body":"B"}],
       "pendingUpdateNotification":"1.9.0"}
      """, to: "state.json")
    let store = FileCursorStore(url: dir.file("state.json"))
    try await store.save("msg-42")
    #expect(try await store.load() == "msg-42")
    let object = try #require(ConfigValue.parseObject(Data(dir.read("state.json").utf8)))
    #expect(object["seen"] == .object(["msg-1": .int(1_700_000_000_000)]))
    #expect(object["lastUpdateCheck"] == .int(12345))
    #expect(object["pendingUpdateNotification"] == .string("1.9.0"))
    #expect(object["reminders"]?.arrayValue?.count == 1)
  }

  @Test func saveCreatesTheFileAndDirectory() async throws {
    let dir = TempDirectory()
    let store = FileCursorStore(url: dir.file("share/state.json"))
    try await store.save("x")
    #expect(try await store.load() == "x")
    #expect(try dir.permissions(dir.file("share/state.json")) == 0o600)
  }

  @Test func saveReplacesACorruptFile() async throws {
    let dir = TempDirectory()
    try dir.write("{{{", to: "state.json")
    let store = FileCursorStore(url: dir.file("state.json"))
    try await store.save("x")
    #expect(try await store.load() == "x")
  }

  @Test func savingTheSameIdDoesNotRewriteTheFile() async throws {
    let dir = TempDirectory()
    let path = dir.file("state.json")
    let store = FileCursorStore(url: path)
    try await store.save("x")
    let before = try FileManager.default.attributesOfItem(atPath: path.path)[.modificationDate]
    try await Task.sleep(for: .milliseconds(20))
    try await store.save("x")
    let after = try FileManager.default.attributesOfItem(atPath: path.path)[.modificationDate]
    #expect(before as? Date == after as? Date)
  }
}
