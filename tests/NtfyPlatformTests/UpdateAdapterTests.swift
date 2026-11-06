import Foundation
import NtfyCore
import Testing

@testable import NtfyPlatform

@Suite struct UpdateAdapterTests {
  @Test func theTeamPinRoundTripsAndStartsEmpty() throws {
    let directory = TempDirectory()
    let store = FileTeamPinStore(
      url: FileTeamPinStore.defaultURL(applicationSupport: directory.url))
    #expect(try store.recorded() == nil)
    try store.record("TEAM000001")
    #expect(try store.recorded() == "TEAM000001")
    try store.record("TEAM000002")
    #expect(try store.recorded() == "TEAM000002")
  }

  @Test func aBlankPinFileIsNoPin() throws {
    let directory = TempDirectory()
    try directory.write("  \n", to: FileTeamPinStore.fileName)
    #expect(try FileTeamPinStore(url: directory.file(FileTeamPinStore.fileName)).recorded() == nil)
  }

  @Test func aMissingOrUnsignedBundleHasNoSignature() throws {
    #expect(BundleSigningInspector(bundle: nil).inspect() == .unsigned)
    let directory = TempDirectory()
    #expect(BundleSigningInspector(bundle: directory.file("Nope.app")).inspect() == .unsigned)
    try FileManager.default.createDirectory(
      at: directory.file("Plain.app/Contents"), withIntermediateDirectories: true)
    #expect(BundleSigningInspector(bundle: directory.file("Plain.app")).inspect() == .unsigned)
  }

  @Test func aSystemAppIsNotDeveloperIDSigned() {
    let info = BundleSigningInspector(bundle: URL(filePath: "/System/Applications/Calculator.app"))
      .inspect()
    #expect(!info.developerID)
  }

  @Test func theTestProcessHoldsNoRestrictedEntitlement() {
    #expect(!ProcessEntitlements().holds(.timeSensitiveNotifications))
  }
}
