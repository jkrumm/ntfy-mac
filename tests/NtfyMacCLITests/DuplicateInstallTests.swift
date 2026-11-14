import Foundation
import Testing

@testable import NtfyMacCLI

@Suite struct DuplicateInstallTests {
  private let scratch = Scratch()

  @discardableResult
  private func bundle(_ path: String) throws -> URL {
    let url = scratch.file(path)
    try FileManager.default.createDirectory(
      at: url.appending(path: "Contents/MacOS"), withIntermediateDirectories: true)
    try Data().write(to: url.appending(path: "Contents/MacOS/ntfy-mac"))
    return url
  }

  private func link(_ path: String, to target: URL) throws -> URL {
    let url = scratch.file(path)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
    return url
  }

  private func executable(_ app: URL) -> String {
    app.appending(path: "Contents/MacOS/ntfy-mac").path
  }

  @Test func oneCopyPasses() throws {
    let direct = try bundle("home/Applications/NtfyMac.app")
    let missing = scratch.file("brew/opt/ntfy-mac/NtfyMac.app")
    let check = DuplicateInstall.check(
      candidates: [direct, missing], runningExecutable: executable(direct))
    #expect(check.status == .passed)
  }

  @Test func aLinkIntoTheBrewCopyIsOneCopy() throws {
    let cellar = try bundle("brew/Cellar/ntfy-mac/2.0.0/NtfyMac.app")
    let opt = try link("brew/opt/ntfy-mac/NtfyMac.app", to: cellar)
    let home = try link("home/Applications/NtfyMac.app", to: opt)
    let copies = DuplicateInstall.copies(
      among: [home, opt], runningExecutable: executable(opt))
    #expect(copies.count == 1)
    #expect(copies.first?.channel == .homebrew)
    #expect(copies.first?.isRunning == true)
    #expect(
      DuplicateInstall.check(candidates: [home, opt], runningExecutable: executable(opt)).status
        == .passed)
  }

  @Test func aBrewAndADirectCopyWarnAndNameTheRunningOne() throws {
    let cellar = try bundle("brew/Cellar/ntfy-mac/2.0.0/NtfyMac.app")
    let opt = try link("brew/opt/ntfy-mac/NtfyMac.app", to: cellar)
    let direct = try bundle("home/Applications/NtfyMac.app")
    let check = DuplicateInstall.check(
      candidates: [direct, opt], runningExecutable: executable(direct))
    #expect(check.status == .warn)
    let detail = try #require(check.detail)
    #expect(detail.contains("\(direct.path) (direct) <- running"))
    #expect(detail.contains("(Homebrew)"))
    #expect(detail.contains("runs from \(direct.path)"))
    #expect(detail.contains("brew uninstall --formula ntfy-mac"))
    #expect(detail.contains("~/.local/bin/ntfy-mac"))
  }

  @Test func twoDirectCopiesWarn() throws {
    let user = try bundle("home/Applications/NtfyMac.app")
    let system = try bundle("system/Applications/NtfyMac.app")
    let check = DuplicateInstall.check(
      candidates: [user, system], runningExecutable: "/elsewhere/ntfy-mac")
    #expect(check.status == .warn)
    #expect(check.detail?.contains("runs from none of them") == true)
  }

  @Test func doctorReportsItWithoutFailing() async throws {
    var rig = CLIRig()
    rig.appCandidates = [
      try rig.bundle("one/NtfyMac.app"), try rig.bundle("two/NtfyMac.app"),
    ]
    let result = await rig.run("doctor", "--json")
    #expect(result.exit == .success)
    let list = try #require(try result.json()["checks"] as? [[String: Any]])
    let check = try #require(list.first { $0["name"] as? String == "duplicate-install" })
    #expect(check["status"] as? String == "warn")
  }
}

extension CLIRig {
  fileprivate func bundle(_ path: String) throws -> URL {
    let url = scratch.file(path)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }
}
