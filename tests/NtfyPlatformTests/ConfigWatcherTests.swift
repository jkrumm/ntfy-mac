import Foundation
import NtfyCore
import Testing

@testable import NtfyPlatform

private actor SignalCounter {
  private(set) var value = 0
  func increment() { value += 1 }
}

/// One consumer per watch; counts the signals it sees.
private struct Watch {
  let counter = SignalCounter()
  let consumer: Task<Void, Never>

  init(file: URL, debounce: Duration = .milliseconds(50)) {
    let stream = ConfigWatcher(file: file, debounce: debounce).changes()
    let counter = counter
    consumer = Task { for await _ in stream { await counter.increment() } }
  }
}

/// Polls `condition` every 20 ms; false once `cap` has passed.
private func eventually(
  within cap: Duration = .seconds(10), _ condition: () async -> Bool
) async -> Bool {
  let deadline = ContinuousClock.now + cap
  while ContinuousClock.now < deadline {
    if await condition() { return true }
    try? await Task.sleep(for: .milliseconds(20))
  }
  return await condition()
}

@Suite(.serialized) struct ConfigWatcherTests {
  @Test func signalsAfterAnAtomicSave() async throws {
    let dir = TempDirectory()
    let path = dir.file("config.json")
    try dir.write(#"{"url":"https://a.example.com"}"#, to: "config.json")
    let watch = Watch(file: path)
    defer { watch.consumer.cancel() }
    try await FileConfigStore(url: path).save(Config(url: "https://b.example.com"))
    #expect(await eventually { await watch.counter.value >= 1 })
  }

  @Test func signalsWhenTheFileIsFirstCreatedInAMissingDirectory() async throws {
    let dir = TempDirectory()
    let path = dir.file("fresh/config.json")
    let watch = Watch(file: path)
    defer { watch.consumer.cancel() }
    try await FileConfigStore(url: path).save(Config(url: "https://b.example.com"))
    #expect(await eventually { await watch.counter.value >= 1 })
  }

  @Test func unrelatedFilesStayQuiet() async throws {
    let dir = TempDirectory()
    let path = dir.file("config.json")
    try dir.write("{}", to: "config.json")
    let watch = Watch(file: path)
    defer { watch.consumer.cancel() }
    try dir.write("x", to: "other.txt")
    // No signal can be awaited for an absence: give the debounce several windows to misfire.
    try await Task.sleep(for: .milliseconds(300))
    #expect(await watch.counter.value == 0)
    // The watch is alive: a real change still comes through.
    try await FileConfigStore(url: path).save(Config(url: "https://n.example.com"))
    #expect(await eventually { await watch.counter.value == 1 })
  }

  @Test func burstOfWritesCollapsesToOneSignal() async throws {
    let dir = TempDirectory()
    let path = dir.file("config.json")
    try dir.write("{}", to: "config.json")
    let watch = Watch(file: path, debounce: .milliseconds(200))
    defer { watch.consumer.cancel() }
    let store = FileConfigStore(url: path)
    for index in 0..<5 { try await store.save(Config(url: "https://n\(index).example.com")) }
    #expect(await eventually { await watch.counter.value >= 1 })
    try await Task.sleep(for: .milliseconds(600))
    #expect(await watch.counter.value == 1)
  }

  @Test func cancellingTheConsumerEndsIterationAndReleasesDescriptors() async throws {
    let dir = TempDirectory()
    let path = dir.file("config.json")
    let before = openDescriptorCount()
    var watches: [Watch] = []
    for _ in 0..<30 { watches.append(Watch(file: path)) }
    #expect(openDescriptorCount() >= before + 30)
    for watch in watches { watch.consumer.cancel() }
    for watch in watches { await watch.consumer.value }
    #expect(await eventually { openDescriptorCount() <= before + 10 })
  }

  private func openDescriptorCount() -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0
  }
}
