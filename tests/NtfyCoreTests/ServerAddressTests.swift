import NtfyCore
import Testing

@Suite struct ServerAddressTests {
  @Test func aBareHostGetsHttpsAndTrailingSlashesGo() throws {
    #expect(
      try ServerAddress.parse(" ntfy.example.com// ").absoluteString == "https://ntfy.example.com")
    #expect(
      try ServerAddress.parse("http://localhost:8080/").absoluteString == "http://localhost:8080")
    #expect(
      try ServerAddress.parse("https://example.com/ntfy/").absoluteString
        == "https://example.com/ntfy")
  }

  @Test func theErrorsSayWhatIsWrong() {
    #expect(throws: ServerAddressError.empty) { try ServerAddress.parse("  ") }
    #expect(throws: ServerAddressError.unsupportedScheme("ftp")) {
      try ServerAddress.parse("ftp://x.example.com")
    }
    #expect(throws: ServerAddressError.invalid("https://")) { try ServerAddress.parse("https://") }
    #expect(ServerAddressError.unsupportedScheme("ftp").description.contains("got ftp:"))
  }
}
