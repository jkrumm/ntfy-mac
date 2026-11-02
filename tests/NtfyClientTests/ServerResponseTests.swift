import Foundation
import NtfyCore
import Testing

@testable import NtfyClient

@Suite struct RetryAfterTests {
  private let now = Date(timeIntervalSince1970: 1_700_000_000)

  @Test(arguments: [("30", 30), ("0", 0), (" 7 ", 7), ("999999999", RetryAfter.cap)])
  func parsesSeconds(header: String, expected: Int) {
    #expect(RetryAfter.seconds(from: header, now: now) == expected)
  }

  @Test(arguments: ["-5", "+5", "1.5", "soon", "", "   "])
  func ignoresGarbageAndNegatives(header: String) {
    #expect(RetryAfter.seconds(from: header, now: now) == nil)
  }

  @Test func capsNumbersTooLargeForAnInt() {
    #expect(RetryAfter.seconds(from: "99999999999999999999999", now: now) == RetryAfter.cap)
  }

  @Test func missingHeaderIsNil() {
    #expect(RetryAfter.seconds(from: nil, now: now) == nil)
  }

  @Test func parsesHttpDates() {
    // 1_700_000_000 is Tue, 14 Nov 2023 22:13:20 GMT.
    #expect(RetryAfter.seconds(from: "Tue, 14 Nov 2023 22:14:20 GMT", now: now) == 60)
    #expect(RetryAfter.seconds(from: "Tue, 14 Nov 2023 22:13:20 GMT", now: now) == 0)
  }

  @Test func ignoresPastAndMalformedDates() {
    #expect(RetryAfter.seconds(from: "Tue, 14 Nov 2023 22:00:00 GMT", now: now) == nil)
    #expect(RetryAfter.seconds(from: "14 Nov 2023", now: now) == nil)
  }

  @Test func capsFarFutureDates() {
    #expect(RetryAfter.seconds(from: "Fri, 01 Jan 2100 00:00:00 GMT", now: now) == RetryAfter.cap)
  }
}
