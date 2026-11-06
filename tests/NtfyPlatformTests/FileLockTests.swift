import Foundation
import NtfyCore
import Synchronization
import Testing

@testable import NtfyPlatform

/// A Sendable home for the mutexes: Swift 6.2 refuses to send a closure that captures a local `Mutex`.
private final class HolderState: Sendable {
  let order = Mutex<[String]>([])
  let held = Mutex(false)
}

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

  @Test func theLockIsReleasedWhenTheBodyThrows() async throws {
    let dir = TempDirectory()
    let lock = dir.file("x.lock")
    #expect(throws: NtfyError.self) {
      try FileLock.withExclusive(lock) { () throws(NtfyError) in throw .storage("boom") }
    }
    let ran = try FileLock.withExclusive(lock) { () throws(NtfyError) -> Bool in true }
    #expect(ran)
  }

  @Test func aSecondHolderWaitsUntilTheFirstIsDone() async throws {
    let dir = TempDirectory()
    let lock = dir.file("x.lock")
    let state = HolderState()
    let first = Task.detached {
      try? FileLock.withExclusive(lock) { () throws(NtfyError) in
        state.held.withLock { $0 = true }
        Thread.sleep(forTimeInterval: 0.3)
        state.order.withLock { $0.append("first") }
      }
    }
    while !state.held.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(5)) }
    let second = Task.detached {
      try? FileLock.withExclusive(lock) { () throws(NtfyError) in
        state.order.withLock { $0.append("second") }
      }
    }
    await first.value
    await second.value
    #expect(state.order.withLock { $0 } == ["first", "second"])
  }
}
