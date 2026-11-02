import ArgumentParser
import NtfyCore
import NtfyIPC
import Testing

@testable import NtfyMacCLI

@Suite struct ProcessExitTests {
  @Test(arguments: [
    (NtfyError.unauthorized, ProcessExit.auth),
    (.serverUnreachable, .serverUnreachable),
    (.appUnavailable, .appUnavailable),
    (.permissionDenied, .appUnavailable),
    (.invalidResponse("x"), .runtime),
    (.storage("x"), .runtime),
    (.rateLimited(retryAfter: 5), .runtime),
    (.redirected, .runtime),
    (.invalidTopic("x y"), .usage),
  ])
  func mapsCoreErrors(error: NtfyError, expected: ProcessExit) {
    #expect(ProcessExit(error: error) == expected)
  }

  @Test func mapsOtherErrors() {
    #expect(ProcessExit(error: ValidationError("bad flag")) == .usage)
    #expect(ProcessExit(error: IPCError.malformedFrame) == .runtime)
    struct Unknown: Error {}
    #expect(ProcessExit(error: Unknown()) == .runtime)
  }

  @Test func rawValuesAreThePublishedCodes() {
    #expect(ProcessExit.allCases.map(\.rawValue) == [0, 1, 2, 3, 4, 7])
  }
}
