import Foundation
import NtfyCore
import NtfyTesting
import Testing

@testable import NtfyClient

@Suite struct URLSessionAttachmentFetcherTests {
  static let payload = Data("attachment bytes".utf8)

  private let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("ntfy-mac-attachment-tests-\(UUID().uuidString)", isDirectory: true)

  private func fetcher(
    server: URL, token: String? = "tk", allowInsecure: Bool = false, maxBytes: Int64 = 1024,
    totalTimeout: Duration = .seconds(120), resolver: StubHostResolver = .public8888
  ) -> URLSessionAttachmentFetcher {
    URLSessionAttachmentFetcher(
      server: server, token: { token }, allowInsecure: allowInsecure, maxBytes: maxBytes,
      totalTimeout: totalTimeout, session: StubURLProtocol.session(), directory: directory,
      resolver: resolver)
  }

  private func file(_ data: Data = payload, status: Int = 200, headers: [String: String] = [:])
    -> Stub
  {
    Stub(
      status: status, headers: ["Content-Type": "application/octet-stream"].merging(headers) { $1 },
      body: data)
  }

  private func attachment(_ url: URL, name: String? = "report.pdf", size: Int64? = nil)
    -> MessageAttachment
  {
    MessageAttachment(url: url, name: name, mimeType: "application/pdf", size: size)
  }

  private func mode(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? Int) ?? -1
  }

  private func expectRefusal(
    _ work: () async throws(NtfyError) -> URL, sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    do {
      _ = try await work()
      Issue.record("expected a refusal", sourceLocation: sourceLocation)
    } catch {}
  }

  // MARK: Credentials

  @Test func sameOriginGetsTheTokenAndOtherOriginsNever() async throws {
    let base = StubURLProtocol.register(file())
    let other = StubURLProtocol.register(file())
    let subject = fetcher(server: base)
    _ = try await subject.fetch(attachment(base.appending(path: "f")))
    _ = try await subject.fetch(attachment(other.appending(path: "f")))
    #expect(
      StubURLProtocol.requests(for: base).first?.value(forHTTPHeaderField: "Authorization")
        == "Bearer tk")
    #expect(
      StubURLProtocol.requests(for: other).first?.value(forHTTPHeaderField: "Authorization")
        == nil)
  }

  @Test func plainHttpServerKeepsTheTokenBackUnlessAllowed() async throws {
    let base = StubURLProtocol.register(file(), scheme: "http")
    _ = try await fetcher(server: base).fetch(attachment(base))
    #expect(
      StubURLProtocol.requests(for: base).first?.value(forHTTPHeaderField: "Authorization")
        == nil)
    let allowed = StubURLProtocol.register(file(), scheme: "http")
    _ = try await fetcher(server: allowed, allowInsecure: true).fetch(attachment(allowed))
    #expect(
      StubURLProtocol.requests(for: allowed).first?.value(forHTTPHeaderField: "Authorization")
        == "Bearer tk")
  }

  // MARK: Refusals

  @Test func plainHttpIsOnlyFetchedFromTheServersOwnOrigin() async throws {
    let server = StubURLProtocol.register(file())
    let other = StubURLProtocol.register(file(), scheme: "http")
    await expectRefusal { () async throws(NtfyError) in
      try await fetcher(server: server).fetch(attachment(other))
    }
    #expect(StubURLProtocol.requests(for: other).isEmpty)
    let own = StubURLProtocol.register(file(), scheme: "http")
    _ = try await fetcher(server: own).fetch(attachment(own))
  }

  @Test(arguments: ["file:///etc/passwd", "ftp://example.com/a", "data:text/plain,hi"])
  func otherSchemesAreRefused(_ text: String) async throws {
    let server = StubURLProtocol.register(file())
    let url = try #require(URL(string: text))
    await expectRefusal { () async throws(NtfyError) in
      try await fetcher(server: server).fetch(attachment(url))
    }
  }

  @Test func aPrivateHostIsRefusedUnlessItIsTheServer() async throws {
    let server = StubURLProtocol.register(file())
    let other = StubURLProtocol.register(file())
    let resolver = StubHostResolver([other.host() ?? "": ["10.0.0.7"]])
    await expectRefusal { () async throws(NtfyError) in
      try await fetcher(server: server, resolver: resolver).fetch(attachment(other))
    }
    #expect(StubURLProtocol.requests(for: other).isEmpty)
    _ = try await fetcher(server: server, resolver: StubHostResolver()).fetch(attachment(server))
  }

  @Test func redirectIsNotFollowed() async {
    let target = StubURLProtocol.register(file())
    let base = StubURLProtocol.register(Stub(redirectTo: target))
    await expectRefusal { () async throws(NtfyError) in
      try await fetcher(server: base).fetch(attachment(base))
    }
    #expect(StubURLProtocol.requests(for: target).isEmpty)
  }

  @Test func statusesMapToTypedErrors() async {
    for (status, expected) in [
      (401, NtfyError.unauthorized), (403, .unauthorized), (500, .serverUnreachable),
      (404, .invalidResponse("HTTP 404")),
    ] {
      let base = StubURLProtocol.register(file(status: status))
      do {
        _ = try await fetcher(server: base).fetch(attachment(base))
        Issue.record("status \(status) must fail")
      } catch {
        #expect(error == expected)
      }
    }
  }

  @Test func silentServerTimesOut() async {
    let base = StubURLProtocol.register(Stub(stall: true))
    do {
      _ = try await fetcher(server: base, totalTimeout: .milliseconds(100)).fetch(attachment(base))
      Issue.record("must time out")
    } catch {
      #expect(error == .serverUnreachable)
    }
  }

  // MARK: Size cap

  @Test func declaredSizeOverTheCapNeverRequests() async {
    let base = StubURLProtocol.register(file())
    await expectRefusal { () async throws(NtfyError) in
      try await fetcher(server: base, maxBytes: 100).fetch(attachment(base, size: 101))
    }
    #expect(StubURLProtocol.requests(for: base).isEmpty)
  }

  @Test func contentLengthOverTheCapIsRejectedByHeader() async {
    let base = StubURLProtocol.register(file(headers: ["Content-Length": "101"]))
    await expectRefusal { () async throws(NtfyError) in
      try await fetcher(server: base, maxBytes: 100).fetch(attachment(base))
    }
  }

  @Test func streamedOversizeIsAbortedAndLeavesNothingBehind() async throws {
    let body = Data(count: 500)
    let missing = StubURLProtocol.register(file(body))
    await expectRefusal { () async throws(NtfyError) in
      try await fetcher(server: missing, maxBytes: 100).fetch(attachment(missing))
    }
    let lying = StubURLProtocol.register(file(body, headers: ["Content-Length": "10"]))
    await expectRefusal { () async throws(NtfyError) in
      try await fetcher(server: lying, maxBytes: 100).fetch(attachment(lying))
    }
    let left = try FileManager.default.contentsOfDirectory(atPath: directory.path)
    #expect(left.isEmpty)
  }

  @Test func aBodyExactlyAtTheCapIsStoredWhole() async throws {
    let body = Data(repeating: 7, count: 100)
    let base = StubURLProtocol.register(file(body))
    let stored = try await fetcher(server: base, maxBytes: 100).fetch(attachment(base))
    #expect(try Data(contentsOf: stored) == body)
  }

  @Test func aBodyOneByteOverTheCapFailsAndLeavesNothingBehind() async throws {
    let base = StubURLProtocol.register(file(Data(repeating: 7, count: 101)))
    await expectRefusal { () async throws(NtfyError) in
      try await fetcher(server: base, maxBytes: 100).fetch(attachment(base))
    }
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
  }

  @Test func aLargeBodyArrivesWholeThroughSeveralChunks() async throws {
    let body = Data((0..<200_000).map { UInt8($0 % 251) })
    let base = StubURLProtocol.register(file(body))
    let stored = try await fetcher(server: base, maxBytes: 200_000).fetch(attachment(base))
    #expect(try Data(contentsOf: stored) == body)
  }

  @Test func theCapItselfIsFiftyMegabytes() {
    #expect(URLSessionAttachmentFetcher.maxBytes == 50 * 1024 * 1024)
  }

  // MARK: Storage

  @Test func theFileLandsPrivatelyUnderAHashedFolderWithTheSanitisedName() async throws {
    let base = StubURLProtocol.register(file())
    let url = try await fetcher(server: base).fetch(attachment(base))
    #expect(url.lastPathComponent == "report.pdf")
    #expect(try Data(contentsOf: url) == Self.payload)
    #expect(try mode(url) == 0o600)
    #expect(try mode(url.deletingLastPathComponent()) == 0o700)
    #expect(try mode(directory) == 0o700)
    let folder = url.deletingLastPathComponent()
    #expect(folder.deletingLastPathComponent() == directory)
    #expect(folder.lastPathComponent == URLSessionAttachmentFetcher.folderName(for: base))
    #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path) == ["report.pdf"])
  }

  @Test(arguments: [
    ("../../etc/passwd", "passwd"), ("..\\..\\evil.sh", "evil.sh"), (".hidden", "hidden"),
    ("a:b.txt", "ab.txt"), ("..", "attachment"), ("", "attachment"), ("/", "attachment"),
    ("bad\u{0}name\n.png", "badname.png"), ("  spaced.txt ", "spaced.txt"),
  ])
  func namesCannotLeaveTheirFolder(_ raw: String, _ expected: String) throws {
    let url = try #require(URL(string: "https://example.com/x"))
    let name = URLSessionAttachmentFetcher.fileName(
      for: MessageAttachment(url: url, name: raw))
    #expect(name == expected)
  }

  @Test func aMissingNameFallsBackToTheURLAndALongNameKeepsItsExtension() throws {
    let url = try #require(URL(string: "https://example.com/files/photo.jpg"))
    #expect(URLSessionAttachmentFetcher.fileName(for: MessageAttachment(url: url)) == "photo.jpg")
    let long = String(repeating: "a", count: 300) + ".pdf"
    let name = URLSessionAttachmentFetcher.fileName(for: MessageAttachment(url: url, name: long))
    #expect(name.count == 104)
    #expect(name.hasSuffix(".pdf"))
  }

  @Test func theSameAttachmentIsReusedWithoutAnotherRequest() async throws {
    let base = StubURLProtocol.register(file())
    let subject = fetcher(server: base)
    let first = try await subject.fetch(attachment(base))
    let second = try await subject.fetch(attachment(base))
    #expect(first == second)
    #expect(StubURLProtocol.requests(for: base).count == 1)
  }

  @Test func pruneRemovesOnlyFoldersNotUsedForAWeek() async throws {
    let base = StubURLProtocol.register(file())
    let other = StubURLProtocol.register(file())
    let subject = fetcher(server: base)
    let old = try await subject.fetch(attachment(base))
    let recent = try await subject.fetch(attachment(other))
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(-8 * 24 * 3600)],
      ofItemAtPath: old.deletingLastPathComponent().path)
    subject.prune()
    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(FileManager.default.fileExists(atPath: recent.path))
  }

  @Test func reuseKeepsAnAttachmentFromBeingPruned() async throws {
    let base = StubURLProtocol.register(file())
    let subject = fetcher(server: base)
    let url = try await subject.fetch(attachment(base))
    try FileManager.default.setAttributes(
      [.modificationDate: Date().addingTimeInterval(-8 * 24 * 3600)],
      ofItemAtPath: url.deletingLastPathComponent().path)
    _ = try await subject.fetch(attachment(base))
    subject.prune()
    #expect(FileManager.default.fileExists(atPath: url.path))
  }
}
