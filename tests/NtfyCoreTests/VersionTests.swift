import Testing

@testable import NtfyCore

@Suite struct VersionTests {
  @Test func bannerCombinesNameAndVersion() {
    #expect(Version.banner() == "ntfy-mac \(Version.current)")
    #expect(Version.banner(name: "x") == "x 2.0.0-dev")
  }
}
