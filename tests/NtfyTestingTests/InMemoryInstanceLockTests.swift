import NtfyCore
import Testing

@testable import NtfyTesting

@Suite struct InMemoryInstanceLockTests {
  @Test func oneHolderAtATimeAndAStaleLeaseChangesNothing() throws {
    let lock = InMemoryInstanceLock()
    let first = try #require(try lock.acquire())
    #expect(try lock.acquire() == nil)
    first.release()
    let second = try #require(try lock.acquire())
    first.release()  // the first lease no longer holds anything
    #expect(lock.isHeld)
    second.release()
    #expect(!lock.isHeld)
  }

  @Test func aScriptedFailureThrows() {
    #expect(throws: NtfyError.self) { try InMemoryInstanceLock(failure: .storage("x")).acquire() }
  }
}
