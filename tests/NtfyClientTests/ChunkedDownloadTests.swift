import Foundation
import NtfyCore
import NtfyTesting
import Testing

@testable import NtfyClient

@Suite struct ChunkedDownloadTests {
  /// Runs `work` and reports whether it finished within `limit`, so a hang fails the test
  /// instead of stalling the suite.
  private func finishes(
    within limit: Duration = .seconds(5), _ work: @escaping @Sendable () async -> Void
  ) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        await work()
        return true
      }
      group.addTask {
        try? await Task.sleep(for: limit)
        return false
      }
      let first = await group.next() ?? false
      group.cancelAll()
      return first
    }
  }

  private func handle() throws -> FileHandle {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("ntfy-mac-chunked-\(UUID().uuidString)")
    FileManager.default.createFile(atPath: url.path, contents: nil)
    return try FileHandle(forWritingTo: url)
  }

  private func request(_ base: URL) -> URLRequest { URLRequest(url: base) }

  @Test func aTaskCancelledBeforeItStartsReturnsPromptly() async throws {
    let base = StubURLProtocol.register(Stub(stall: true))
    let (session, file) = (StubURLProtocol.session(), try handle())
    let request = request(base)
    let done = await finishes {
      let task = Task {
        try await ChunkedDownload.run(request, on: session, limit: 100, into: file)
      }
      task.cancel()
      _ = await task.result
    }
    #expect(done, "a download cancelled before it starts must not hang")
  }

  @Test func aTaskCancelledMidDownloadReturnsPromptly() async throws {
    let base = StubURLProtocol.register(
      Stub(headers: ["Content-Type": "application/octet-stream"], body: Data(count: 10), hold: true)
    )
    let (session, file) = (StubURLProtocol.session(), try handle())
    let request = request(base)
    let done = await finishes {
      let task = Task {
        try await ChunkedDownload.run(request, on: session, limit: 100, into: file)
      }
      while StubURLProtocol.requests(for: base).isEmpty, !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(5))
      }
      task.cancel()
      _ = await task.result
    }
    #expect(done, "a download cancelled mid-flight must not hang")
    #expect(await StubURLProtocol.waitUntilStopped(base))
  }

  @Test func aFetchCancelledMidDownloadReturnsPromptly() async {
    let base = StubURLProtocol.register(Stub(hold: true))
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("ntfy-mac-chunked-fetch-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let subject = URLSessionAttachmentFetcher(
      server: base, token: { nil }, session: StubURLProtocol.session(), directory: directory,
      resolver: StubHostResolver.public8888)
    let item = MessageAttachment(url: base, name: "a.bin", mimeType: nil, size: nil)
    let done = await finishes {
      let task = Task { _ = try? await subject.fetch(item) }
      while StubURLProtocol.requests(for: base).isEmpty, !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(5))
      }
      task.cancel()
      await task.value
    }
    #expect(done, "a cancelled fetch must not hang")
  }
}
