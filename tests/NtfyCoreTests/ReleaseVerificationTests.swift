import Foundation
import Testing

@testable import NtfyCore

@Suite struct ReleaseVerificationTests {
  private static let digest = String(repeating: "ab", count: 32)
  private static let file = "ntfy-mac-2.0.0-arm64.tar.gz"

  private func parse(_ text: String) throws(ReleaseUpdateError) -> ReleaseChecksums {
    try ReleaseChecksums(parsing: text)
  }

  @Test func acceptsTheMatchingDigest() throws {
    let sums = try parse(
      "\(Self.digest)  \(Self.file)\n\(String(repeating: "0", count: 64))  other\n")
    try sums.verify(digest: Self.digest, of: Self.file)
  }

  @Test func digestCaseDoesNotMatter() throws {
    let sums = try parse("\(Self.digest.uppercased())  \(Self.file)")
    try sums.verify(digest: Self.digest, of: Self.file)
    try sums.verify(digest: Self.digest.uppercased(), of: Self.file)
  }

  @Test func windowsLineEndingsAreTolerated() throws {
    try parse("\(Self.digest)  \(Self.file)\r\n").verify(digest: Self.digest, of: Self.file)
  }

  @Test func aWrongDigestIsAMismatch() throws {
    let sums = try parse("\(Self.digest)  \(Self.file)")
    #expect(throws: ReleaseUpdateError.checksumMismatch(Self.file)) {
      try sums.verify(digest: String(repeating: "cd", count: 32), of: Self.file)
    }
  }

  @Test func aMissingEntryFailsClosed() throws {
    let sums = try parse("\(Self.digest)  something-else")
    #expect(throws: ReleaseUpdateError.checksumMissing(Self.file)) {
      try sums.verify(digest: Self.digest, of: Self.file)
    }
  }

  @Test func aSimilarFileNameDoesNotMatch() throws {
    let sums = try parse("\(Self.digest)  \(Self.file).sig")
    #expect(throws: ReleaseUpdateError.checksumMissing(Self.file)) {
      try sums.verify(digest: Self.digest, of: Self.file)
    }
  }

  @Test func duplicateEntriesAreRejectedEvenWhenIdentical() {
    let line = "\(Self.digest)  \(Self.file)"
    #expect(throws: ReleaseUpdateError.checksumsDuplicate(Self.file)) {
      try parse("\(line)\n\(line)\n")
    }
  }

  @Test(arguments: [
    "garbage",
    "abc  \(file)",
    "\(digest) \(file)",
    "\(digest)\t\(file)",
    "\(digest)  ",
    "\(String(repeating: "z", count: 64))  \(file)",
    "\(digest)a  \(file)",
    "\(digest)   \(file)",
  ])
  func malformedLinesAreRejected(line: String) {
    #expect(throws: ReleaseUpdateError.checksumsMalformed(line: 2)) {
      try parse("\(Self.digest)  first\n\(line)\n")
    }
  }

  @Test func anEmptyFileHasNoEntries() throws {
    #expect(throws: ReleaseUpdateError.checksumMissing(Self.file)) {
      try parse("").verify(digest: Self.digest, of: Self.file)
    }
  }

  @Test func hashesAFileInChunks() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ntfy-mac-digest-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data("abc".utf8).write(to: url)
    #expect(
      try FileDigest.sha256Hex(of: url)
        == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
  }

  // MARK: archive entries

  @Test(arguments: [
    ["NtfyMac.app/", "NtfyMac.app/Contents/Info.plist", "LICENSE"],
    ["./NtfyMac.app/", "./NtfyMac.app/Contents/MacOS/ntfy-mac", "./LICENSE", "./"],
    [],
  ])
  func expectedEntriesPass(entries: [String]) throws {
    try ReleasePolicy.validate(entries: entries)
  }

  @Test(arguments: [
    "/etc/passwd", "/NtfyMac.app/x", "../evil", "NtfyMac.app/../../evil", "NtfyMac.app/..",
    "./../evil", "evil.sh", "NtfyMac.app.bak/x", "LICENSE/inner", "NtfyMac.app/a\nb",
    ".hidden",
  ])
  func unsafeEntriesAreRejected(entry: String) {
    #expect(throws: ReleaseUpdateError.unsafeArchiveEntry(entry)) {
      try ReleasePolicy.validate(entries: ["NtfyMac.app/", entry])
    }
  }

  // MARK: download URLs

  @Test(arguments: [
    "https://github.com/jkrumm/ntfy-mac/releases/download/v2.0.0/SHA256SUMS",
    "https://objects.githubusercontent.com/github-production-release-asset/1",
    "https://release-assets.githubusercontent.com/x",
    "https://GitHub.com/a/b",
  ])
  func githubHostsAreAllowed(url: String) throws {
    #expect(ReleasePolicy.isAllowed(try #require(URL(string: url))))
  }

  @Test(arguments: [
    "http://github.com/a/b", "https://evil.example/a", "https://github.com.evil.example/a",
    "https://evil.example/github.com", "https://user@github.com/a", "https://github.com:8443/a",
    "ftp://github.com/a", "https://api.github.com/a", "https://raw.githubusercontent.com/a",
    "file:///etc/passwd",
  ])
  func everythingElseIsRefused(url: String) throws {
    #expect(!ReleasePolicy.isAllowed(try #require(URL(string: url))))
  }
}
