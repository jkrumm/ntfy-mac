import Foundation
import NtfyCore
import Testing

@testable import NtfyPlatform

@Suite struct FileLockTests {
  /// Two stores on one file stand in for the app and the CLI: separate actors, so only the file
  /// lock can keep their read-modify-write cycles from interleaving.
  @Test func concurrentWritersFromTwoStoresLoseNoUpdate() async throws {
    let dir = TempDirectory()
    let file = dir.file("config.json")
    let first = FileConfigStore(url: file)
    let second = FileConfigStore(url: file)
    let count = 40
    try await withThrowingTaskGroup(of: Void.self) { group in
      for index in 0..<count {
        let store = index.isMultiple(of: 2) ? first : second
        group.addTask {
          try await store.update { $0.extraTopics.append("topic-\(index)") }
        }
      }
      try await group.waitForAll()
    }
    let topics = Set(await first.load().extraTopics)
    #expect(topics == Set((0..<count).map { "topic-\($0)" }))
  }

  @Test func theLockSidecarIsPrivateAndTheConfigIsUntouchedByIt() async throws {
    let dir = TempDirectory()
    let store = FileConfigStore(url: dir.file("config.json"))
    try await store.update { $0.url = "https://x.example.com" }
    #expect(try dir.permissions(dir.file("config.json.lock")) == 0o600)
    #expect(await store.load().url == "https://x.example.com")
  }

  @Test func saveTakesTheLockToo() async throws {
    let dir = TempDirectory()
    let store = FileConfigStore(url: dir.file("config.json"))
    try await store.save(Config(url: "https://x.example.com"))
    #expect(FileManager.default.fileExists(atPath: dir.file("config.json.lock").path))
  }

  @Test func theCursorStoreLocksItsWrites() async throws {
    let dir = TempDirectory()
    let store = FileCursorStore(url: dir.file("state.json"))
    try await store.save("abc")
    #expect(try await store.load() == "abc")
    #expect(FileManager.default.fileExists(atPath: dir.file("state.json.lock").path))
  }
}
