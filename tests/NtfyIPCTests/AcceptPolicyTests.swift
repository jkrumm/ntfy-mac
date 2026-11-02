import Darwin
import Testing

@testable import NtfyIPC

@Suite struct AcceptPolicyTests {
  @Test func interruptionsRetryAtOnceAndAClosedListenerEndsTheLoop() {
    #expect(AcceptFailure.classify(EINTR) == .retry)
    #expect(AcceptFailure.classify(ECONNABORTED) == .retry)
    #expect(AcceptFailure.classify(EBADF) == .stop)
    #expect(AcceptFailure.classify(EINVAL) == .stop)
  }

  @Test func resourceFailuresBackOff() {
    #expect(AcceptFailure.classify(EMFILE) == .backOff)
    #expect(AcceptFailure.classify(ENFILE) == .backOff)
    #expect(AcceptFailure.classify(ENOMEM) == .backOff)
  }

  @Test func theBackoffDoublesFromFiftyMillisecondsToOneSecondAndResets() {
    var backoff = AcceptBackoff()
    #expect(backoff.isFirstFailure)
    var delays: [Duration] = []
    for _ in 0..<7 { delays.append(backoff.next()) }
    #expect(
      delays == [
        .milliseconds(50), .milliseconds(100), .milliseconds(200), .milliseconds(400),
        .milliseconds(800), .seconds(1), .seconds(1),
      ])
    #expect(!backoff.isFirstFailure)
    backoff.reset()
    #expect(backoff.isFirstFailure)
    #expect(backoff.next() == .milliseconds(50))
  }
}
