import Foundation
import NtfyCore
import Testing

@testable import NtfyPlatform

@Suite struct SystemToolTests {
  @Test func returnsStatusAndOutput() async throws {
    let result = try await SystemTool.run("/bin/echo", ["hi"], timeout: 5)
    #expect(result.status == 0)
    #expect(String(bytes: result.output, encoding: .utf8) == "hi\n")
  }

  @Test func aToolPastItsDeadlineIsKilledAndReported() async {
    let started = ContinuousClock.now
    await #expect(throws: NtfyError.self) {
      try await SystemTool.run("/bin/sleep", ["120"], timeout: 0.3)
    }
    // Killed, not waited out: a loaded runner can delay the kill by seconds, not by the 120.
    #expect(ContinuousClock.now - started < .seconds(60))
  }

  @Test func aMissingToolIsReported() async {
    await #expect(throws: NtfyError.self) {
      try await SystemTool.run("/nonexistent/tool", [], timeout: 1)
    }
  }
}

@Suite struct LSRegisterParsingTests {
  private let dump = """
    --------------------------------------------------------------------------------
    bundle id:                  1234
    path:                       /Users/John Doe/Applications/ntfy-notify.app (0x4854)
    name:                       ntfy-notify
    --------------------------------------------------------------------------------
    path:                       /Users/me/.local/share/ntfy-mac/ntfy-notify.app (0x4878)
    path:                       /System/Applications/News.app (0x1)
    path:                       /Users/me/ntfy-notify.app.bak/Thing.app (0x2)
    executable:                 /Users/me/ntfy-notify.app/Contents/MacOS/x
    path:                       /Users/John Doe/Applications/ntfy-notify.app (0x9999)
    path:                       /Volumes/Old/ntfy-notify.app
    """

  @Test func readsPathsWithSpacesAndIgnoresEverythingElse() {
    #expect(
      LSRegister.helperPaths(inDump: dump) == [
        "/Users/John Doe/Applications/ntfy-notify.app",
        "/Users/me/.local/share/ntfy-mac/ntfy-notify.app",
        "/Volumes/Old/ntfy-notify.app",
      ])
  }
}
