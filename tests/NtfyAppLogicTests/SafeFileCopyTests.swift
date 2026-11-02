import Foundation
import Testing

@testable import NtfyAppLogic

@Suite struct SafeFileCopyTests {
  private func scratch() throws -> URL {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ntfy-mac-copy-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
  }

  private func write(_ text: String, to url: URL) throws {
    try Data(text.utf8).write(to: url)
  }

  private func read(_ url: URL) throws -> String {
    String(bytes: try Data(contentsOf: url), encoding: .utf8) ?? ""
  }

  @Test func copiesToANewDestination() throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("a.txt")
    let target = dir.appendingPathComponent("b.txt")
    try write("one", to: source)
    try SafeFileCopy.copy(source, to: target)
    #expect(try read(target) == "one")
    #expect(try read(source) == "one")
  }

  @Test func replacesAnExistingDestinationAndLeavesNoTemporaryFile() throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("a.txt")
    let target = dir.appendingPathComponent("b.txt")
    try write("new", to: source)
    try write("old", to: target)
    try SafeFileCopy.copy(source, to: target)
    #expect(try read(target) == "new")
    #expect(
      try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["a.txt", "b.txt"])
  }

  @Test func pickingTheSourceItselfKeepsIt() throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("a.txt")
    try write("keep", to: source)
    try SafeFileCopy.copy(source, to: dir.appendingPathComponent("./a.txt"))
    #expect(try read(source) == "keep")
  }

  @Test func aFailedCopyLeavesTheDestinationAlone() throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let target = dir.appendingPathComponent("b.txt")
    try write("precious", to: target)
    #expect(throws: (any Error).self) {
      try SafeFileCopy.copy(dir.appendingPathComponent("missing.txt"), to: target)
    }
    #expect(try read(target) == "precious")
  }

  @Test func anUnreadableSourceLeavesNoTemporaryFile() throws {
    let dir = try scratch()
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o644], ofItemAtPath: dir.appendingPathComponent("a.txt").path)
      try? FileManager.default.removeItem(at: dir)
    }
    let source = dir.appendingPathComponent("a.txt")
    try write("secret", to: source)
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
    #expect(throws: (any Error).self) {
      try SafeFileCopy.copy(source, to: dir.appendingPathComponent("b.txt"))
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["a.txt"])
  }

  @Test func aDestinationInAMissingFolderFailsWithoutLeavingFiles() throws {
    let dir = try scratch()
    defer { try? FileManager.default.removeItem(at: dir) }
    let source = dir.appendingPathComponent("a.txt")
    try write("new", to: source)
    // The staged copy cannot be made next to a destination whose folder does not exist.
    let target = dir.appendingPathComponent("missing/b.txt")
    #expect(throws: (any Error).self) { try SafeFileCopy.copy(source, to: target) }
    #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path) == ["a.txt"])
  }
}
