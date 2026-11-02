import Darwin
import Foundation
import NtfyCore
import Testing

@testable import NtfyPlatform

@Suite struct UpdateAdapterTests {
  private func folder(_ temp: borrowing TempDirectory, _ name: String, marker: String) throws -> URL
  {
    let url = temp.file(name)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    try Data(marker.utf8).write(to: url.appendingPathComponent("marker"))
    return url
  }

  private func marker(_ url: URL) -> String? {
    (try? Data(contentsOf: url.appendingPathComponent("marker")))
      .map { String(bytes: $0, encoding: .utf8) ?? "" }
  }

  @Test func swapsTwoDirectoriesAndSwapsBack() throws {
    let temp = TempDirectory()
    let first = try folder(temp, "a", marker: "one")
    let second = try folder(temp, "b", marker: "two")
    let swapper = AtomicBundleSwapper()
    try swapper.swap(first, second)
    #expect(marker(first) == "two")
    #expect(marker(second) == "one")
    try swapper.swap(first, second)
    #expect(marker(first) == "one")
  }

  @Test func fallsBackToRenamesWhenTheFileSystemCannotSwap() throws {
    let temp = TempDirectory()
    let first = try folder(temp, "a", marker: "one")
    let second = try folder(temp, "b", marker: "two")
    let swapper = AtomicBundleSwapper(
      exchange: { _, _ in ENOTSUP }, rename: { Darwin.rename($0, $1) == 0 ? 0 : errno })
    try swapper.swap(first, second)
    #expect(marker(first) == "two")
    #expect(marker(second) == "one")
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: temp.url.path).sorted() == ["a", "b"])
  }

  @Test func aFailedFallbackRestoresBothDirectories() throws {
    let temp = TempDirectory()
    let first = try folder(temp, "a", marker: "one")
    let second = try folder(temp, "b", marker: "two")
    let calls = Counter()
    // Let the first rename (aside) through, then fail the second (second into first's place).
    let swapper = AtomicBundleSwapper(
      exchange: { _, _ in EINVAL },
      rename: { source, destination in
        if calls.next() == 2 { return EACCES }
        return Darwin.rename(source, destination) == 0 ? 0 : errno
      })
    #expect(throws: NtfyError.self) { try swapper.swap(first, second) }
    #expect(marker(first) == "one")
    #expect(marker(second) == "two")
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: temp.url.path).sorted() == ["a", "b"])
  }

  @Test func aHardExchangeFailureIsReportedWithoutFallback() throws {
    let temp = TempDirectory()
    let first = try folder(temp, "a", marker: "one")
    let swapper = AtomicBundleSwapper(exchange: { _, _ in EACCES }, rename: { _, _ in 0 })
    #expect(throws: NtfyError.self) { try swapper.swap(first, temp.file("missing")) }
    #expect(marker(first) == "one")
  }
}

private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var value = 0

  func next() -> Int {
    lock.lock()
    defer { lock.unlock() }
    value += 1
    return value
  }
}
