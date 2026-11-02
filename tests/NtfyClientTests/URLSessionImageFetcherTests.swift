import Foundation
import Testing

@testable import NtfyClient

@Suite struct URLSessionImageFetcherTests {
  static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) + Data(count: 32)
  static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0]) + Data(count: 32)
  static let gif = Data("GIF89a".utf8) + Data(count: 32)

  private let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("ntfy-mac-image-tests-\(UUID().uuidString)", isDirectory: true)

  private func fetcher(
    server: URL, token: String? = "tk", allowInsecure: Bool = false,
    totalTimeout: Duration = .seconds(15)
  ) -> URLSessionImageFetcher {
    URLSessionImageFetcher(
      server: server, token: { token }, allowInsecure: allowInsecure,
      totalTimeout: totalTimeout, session: StubURLProtocol.session(), directory: directory)
  }

  private func image(_ data: Data, type: String = "image/png", status: Int = 200) -> Stub {
    Stub(status: status, headers: ["Content-Type": type], body: data)
  }

  private func permissions(_ url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    return (attributes[.posixPermissions] as? Int) ?? -1
  }

  // MARK: Credentials

  @Test func sameOriginGetsTheToken() async {
    let base = StubURLProtocol.register(image(Self.png))
    let file = await fetcher(server: base).fetch(base.appending(path: "a.png"))
    #expect(file != nil)
    #expect(
      StubURLProtocol.requests(for: base).first?.value(forHTTPHeaderField: "Authorization")
        == "Bearer tk")
  }

  @Test func otherOriginNeverGetsTheToken() async {
    let server = StubURLProtocol.register(image(Self.png))
    let other = StubURLProtocol.register(image(Self.png))
    let file = await fetcher(server: server).fetch(other.appending(path: "a.png"))
    #expect(file != nil)
    #expect(
      StubURLProtocol.requests(for: other).first?.value(forHTTPHeaderField: "Authorization")
        == nil)
  }

  @Test func otherPortIsAnotherOrigin() async throws {
    let other = StubURLProtocol.register(image(Self.png))
    let server = try #require(URL(string: "https://\(other.host() ?? ""):8443"))
    _ = await fetcher(server: server).fetch(other)
    #expect(
      StubURLProtocol.requests(for: other).first?.value(forHTTPHeaderField: "Authorization")
        == nil)
  }

  @Test func plainHttpServerKeepsTheTokenBackUnlessAllowed() async {
    let base = StubURLProtocol.register(image(Self.png), scheme: "http")
    _ = await fetcher(server: base).fetch(base)
    #expect(
      StubURLProtocol.requests(for: base).first?.value(forHTTPHeaderField: "Authorization")
        == nil)
    let allowed = StubURLProtocol.register(image(Self.png), scheme: "http")
    _ = await fetcher(server: allowed, allowInsecure: true).fetch(allowed)
    #expect(
      StubURLProtocol.requests(for: allowed).first?.value(forHTTPHeaderField: "Authorization")
        == "Bearer tk")
  }

  // MARK: Refusals

  @Test func redirectIsNotFollowed() async throws {
    let target = StubURLProtocol.register(image(Self.png))
    let base = StubURLProtocol.register(Stub(redirectTo: target))
    #expect(await fetcher(server: base).fetch(base) == nil)
    #expect(StubURLProtocol.requests(for: target).isEmpty)
  }

  @Test func nonImageSchemesAreRefusedWithoutARequest() async throws {
    let base = StubURLProtocol.register(image(Self.png))
    let file = try #require(URL(string: "file:///etc/passwd"))
    #expect(await fetcher(server: base).fetch(file) == nil)
  }

  @Test func errorStatusYieldsNothing() async {
    let base = StubURLProtocol.register(image(Self.png, status: 404))
    #expect(await fetcher(server: base).fetch(base) == nil)
  }

  @Test func wrongMagicBytesAreRejectedDespiteTheContentType() async {
    let base = StubURLProtocol.register(image(Data("<html>not an image</html>".utf8)))
    #expect(await fetcher(server: base).fetch(base) == nil)
  }

  @Test func declaredOversizeIsRejectedByHeader() async {
    let size = URLSessionImageFetcher.maxBytes + 1
    let base = StubURLProtocol.register(
      Stub(
        headers: ["Content-Type": "image/png", "Content-Length": String(size)], body: Self.png))
    #expect(await fetcher(server: base).fetch(base) == nil)
  }

  @Test func streamedOversizeIsAbortedWhenTheHeaderIsMissingOrLies() async {
    let body = Self.png + Data(count: URLSessionImageFetcher.maxBytes)
    let missing = StubURLProtocol.register(image(body))
    #expect(await fetcher(server: missing).fetch(missing) == nil)
    let lying = StubURLProtocol.register(
      Stub(headers: ["Content-Type": "image/png", "Content-Length": "10"], body: body))
    #expect(await fetcher(server: lying).fetch(lying) == nil)
  }

  @Test func silentServerTimesOut() async {
    let base = StubURLProtocol.register(Stub(stall: true))
    let result = await fetcher(server: base, totalTimeout: .milliseconds(100)).fetch(base)
    #expect(result == nil)
  }

  // MARK: Storage

  @Test(arguments: [
    ("png", URLSessionImageFetcherTests.png), ("jpg", URLSessionImageFetcherTests.jpeg),
    ("gif", URLSessionImageFetcherTests.gif),
  ])
  func acceptedImagesLandWithTheRightExtensionInAPrivateDirectory(
    _ fileExtension: String, _ data: Data
  ) async throws {
    let base = StubURLProtocol.register(image(data, type: "application/octet-stream"))
    let file = try #require(await fetcher(server: base).fetch(base))
    #expect(file.pathExtension == fileExtension)
    #expect(try Data(contentsOf: file) == data)
    #expect(try permissions(file.deletingLastPathComponent()) == 0o700)
    #expect(file.deletingLastPathComponent().deletingLastPathComponent() == directory)
  }

  @Test func cleanUpRemovesOnlyOldImages() async throws {
    let base = StubURLProtocol.register(image(Self.png))
    let fetcher = fetcher(server: base)
    let file = try #require(await fetcher.fetch(base))
    fetcher.cleanUp(olderThan: 3600)
    #expect(FileManager.default.fileExists(atPath: file.path))
    fetcher.cleanUp(olderThan: 3600, now: Date().addingTimeInterval(7200))
    #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
  }

  @Test func nextFetchCleansUpOldImages() async throws {
    let base = StubURLProtocol.register(image(Self.png))
    let fetcher = fetcher(server: base)
    let old = try #require(await fetcher.fetch(base))
    let aged = Date().addingTimeInterval(-7200)
    try FileManager.default.setAttributes(
      [.modificationDate: aged], ofItemAtPath: old.deletingLastPathComponent().path)
    let fresh = try #require(await fetcher.fetch(base))
    #expect(!FileManager.default.fileExists(atPath: old.path))
    #expect(FileManager.default.fileExists(atPath: fresh.path))
  }
}
