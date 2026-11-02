import Testing

@testable import NtfyCore

@Suite struct NetworkHostTests {
  @Test(arguments: [
    "0.1.2.3", "198.18.0.1", "198.19.255.255", "192.0.0.8", "192.0.2.1", "198.51.100.7",
    "203.0.113.9", "224.0.0.1", "239.255.255.255", "240.0.0.1", "255.255.255.255",
    "[ff02::1]", "ff00::1", "[::ffff:192.0.2.1]", "[64:ff9b::a00:1]", "[64:ff9b::7f00:1]",
    "[2001:db8::1]", "[2001:db8:ffff::1]", "::ffff:127.0.0.1",
  ])
  func specialAddressesArePrivate(host: String) {
    #expect(NetworkHost.isPrivate(host))
  }

  @Test(arguments: [
    "198.17.255.255", "198.20.0.1", "192.0.1.1", "192.0.3.1", "198.51.99.1", "198.51.101.1",
    "203.0.112.1", "203.0.114.1", "223.255.255.255", "8.8.8.8", "[2606:4700::1111]",
    "[::ffff:8.8.8.8]", "[64:ff9b::808:808]", "[2001:db9::1]", "[2001:4860:4860::8888]",
  ])
  func neighbouringPublicAddressesAreNot(host: String) {
    #expect(!NetworkHost.isPrivate(host))
  }
}

@Suite struct HostSafetyTests {
  private struct Fixed: HostResolving {
    let answer: [String]?
    func addresses(of host: String) async -> [String]? { answer }
  }

  @Test func onlyPublicAnswersPass() async {
    #expect(await HostSafety.resolvesToPublicAddresses("h", using: Fixed(answer: ["8.8.8.8"])))
  }

  @Test(arguments: [["8.8.8.8", "10.0.0.1"], ["::1"], ["fd00::1"], [], ["64:ff9b::a00:1"]])
  func anyPrivateOrEmptyAnswerFails(answer: [String]) async {
    #expect(!(await HostSafety.resolvesToPublicAddresses("h", using: Fixed(answer: answer))))
  }

  @Test func aFailedLookupFails() async {
    #expect(!(await HostSafety.resolvesToPublicAddresses("h", using: Fixed(answer: nil))))
  }
}
