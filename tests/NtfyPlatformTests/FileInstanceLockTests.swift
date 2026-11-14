import Foundation
import NtfyCore
import Testing

@testable import NtfyPlatform

@Suite struct FileInstanceLockTests {
  @Test func theFirstHolderGetsTheLockAndASecondOneDoesNot() throws {
    let dir = TempDirectory()
    let lock = FileInstanceLock(url: dir.file("ntfy-mac/app.instance.lock"))
    let first = try lock.acquire()
    #expect(first != nil)
    #expect(try lock.acquire() == nil)
  }

  @Test func releasingTheLeaseLetsTheNextCopyStart() throws {
    let dir = TempDirectory()
    let lock = FileInstanceLock(url: dir.file("app.instance.lock"))
    let first = try #require(try lock.acquire())
    first.release()
    first.release()  // idempotent
    #expect(try lock.acquire() != nil)
  }

  @Test func aLeaseThatGoesAwayReleasesTheLock() throws {
    let dir = TempDirectory()
    let lock = FileInstanceLock(url: dir.file("app.instance.lock"))
    do { _ = try lock.acquire() }
    #expect(try lock.acquire() != nil)
  }

  @Test func theLockFileAndItsDirectoryArePrivate() throws {
    let dir = TempDirectory()
    let url = dir.file("ntfy-mac/app.instance.lock")
    let lease = try FileInstanceLock(url: url).acquire()
    #expect(lease != nil)
    #expect(try dir.permissions(url) == 0o600)
    #expect(try dir.permissions(url.deletingLastPathComponent()) == 0o700)
  }

  @Test func theDefaultSitsNextToTheSocket() {
    let url = FileInstanceLock.defaultURL(applicationSupport: URL(filePath: "/support"))
    #expect(url.path == "/support/ntfy-mac/app.instance.lock")
  }

  @Test func anUnusableDirectoryIsAStorageError() throws {
    let dir = TempDirectory()
    try dir.write("not a directory", to: "blocker")
    #expect(throws: NtfyError.self) {
      try FileInstanceLock(url: dir.file("blocker/app.instance.lock")).acquire()
    }
  }
}
