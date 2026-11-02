import Foundation
import NtfyCore
import Testing

@testable import NtfyClient

@Suite(.serialized) struct URLSessionReleaseAssetFetcherTests {
  private let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("ntfy-mac-release-fetch-\(UUID().uuidString)", isDirectory: true)

  private func fetcher() -> URLSessionReleaseAssetFetcher {
    URLSessionReleaseAssetFetcher(session: StubURLProtocol.session())
  }

  private func target() throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appendingPathComponent("asset")
  }

  private func binary(_ data: Data, status: Int = 200) -> Stub {
    Stub(status: status, headers: ["Content-Type": "application/octet-stream"], body: data)
  }

  @Test func downloadsFromAnAllowedHostIntoAPrivateFile() async throws {
    let url = StubURLProtocol.register(
      binary(Data("payload".utf8)), host: "objects.githubusercontent.com")
    let file = try target()
    defer { try? FileManager.default.removeItem(at: directory) }
    try await fetcher().download(url, to: file, maxBytes: 1024)
    #expect(try Data(contentsOf: file) == Data("payload".utf8))
    let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions]
    #expect(mode as? Int == 0o600)
  }

  @Test func followsARedirectToTheReleaseCDN() async throws {
    let cdn = StubURLProtocol.register(
      binary(Data("cdn".utf8)), host: "release-assets.githubusercontent.com")
    let url = StubURLProtocol.register(Stub(redirectTo: cdn), host: "github.com")
    let file = try target()
    defer { try? FileManager.default.removeItem(at: directory) }
    try await fetcher().download(url, to: file, maxBytes: 1024)
    #expect(try Data(contentsOf: file) == Data("cdn".utf8))
  }

  @Test func refusesARedirectToAnotherHost() async throws {
    let other = StubURLProtocol.register(binary(Data("evil".utf8)))
    let url = StubURLProtocol.register(
      Stub(redirectTo: other), host: "github-releases.githubusercontent.com")
    let file = try target()
    defer { try? FileManager.default.removeItem(at: directory) }
    await #expect(throws: NtfyError.self) {
      try await fetcher().download(url, to: file, maxBytes: 1024)
    }
    #expect(StubURLProtocol.requests(for: other).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: file.path))
  }

  @Test func refusesAHostOutsideGitHubWithoutConnecting() async throws {
    let url = StubURLProtocol.register(binary(Data("x".utf8)))
    let file = try target()
    defer { try? FileManager.default.removeItem(at: directory) }
    await #expect(throws: NtfyError.self) {
      try await fetcher().download(url, to: file, maxBytes: 1024)
    }
    #expect(StubURLProtocol.requests(for: url).isEmpty)
  }

  @Test func aBodyOverTheCapFailsAndLeavesNoFile() async throws {
    let url = StubURLProtocol.register(
      binary(Data(repeating: 1, count: 64)), host: "objects.githubusercontent.com")
    let file = try target()
    defer { try? FileManager.default.removeItem(at: directory) }
    await #expect(throws: NtfyError.self) {
      try await fetcher().download(url, to: file, maxBytes: 16)
    }
    #expect(!FileManager.default.fileExists(atPath: file.path))
  }
}
