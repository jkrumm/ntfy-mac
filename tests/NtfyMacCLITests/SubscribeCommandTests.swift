import Foundation
import NtfyCore
import Testing

@testable import NtfyMacCLI

@Suite struct SubscribeCommandTests {
  @Test func subscribeAddsATopicOnce() async {
    let rig = CLIRig()
    #expect(await rig.run("subscribe", "builds").stdout == "Subscribed to \"builds\".\n")
    let again = await rig.run("subscribe", "builds")
    #expect(again.exit == .success)
    #expect(again.stdout.contains("already subscribed"))
    #expect(await rig.config.load().extraTopics == ["builds"])
  }

  @Test(arguments: ["has space", "slash/topic", "", String(repeating: "a", count: 65)])
  func invalidTopicNamesAreUsageErrors(name: String) async {
    let rig = CLIRig()
    let result = await rig.run("subscribe", name)
    #expect(result.exit == .usage)
    #expect(await rig.config.load().extraTopics.isEmpty)
  }

  @Test func unsubscribeRemovesALocalTopic() async {
    let rig = CLIRig()
    _ = await rig.run("subscribe", "builds")
    let result = await rig.run("unsubscribe", "builds")
    #expect(result.exit == .success)
    #expect(await rig.config.load().extraTopics.isEmpty)
  }

  @Test func unsubscribingAnUnknownTopicFails() async {
    let result = await CLIRig().run("unsubscribe", "ghost")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("not in the local additions"))
  }

  @Test func resetClearsTheLocalAdditions() async {
    let rig = CLIRig()
    _ = await rig.run("subscribe", "builds")
    #expect(await rig.run("subscribe", "reset").exit == .success)
    #expect(await rig.config.load().extraTopics.isEmpty)
  }

  @Test func listingMergesServerAndLocalTopics() async {
    let rig = CLIRig(topics: ["alerts", "ops"])
    _ = await rig.run("subscribe", "builds")
    let result = await rig.run("subscribe")
    #expect(result.stdout.contains("  alerts\n"))
    #expect(result.stdout.contains("  builds (local)"))
  }

  @Test func listingDegradesWhenTheServerIsDown() async throws {
    let rig = CLIRig(topicFailure: .serverUnreachable)
    _ = await rig.run("subscribe", "builds")
    let result = await rig.run("subscribe", "--json")
    #expect(result.exit == .success)
    #expect(result.stderr.contains("Could not fetch"))
    #expect(try result.json()["serverReachable"] as? Bool == false)
    let topics = try #require(try result.json()["topics"] as? [[String: Any]])
    #expect(topics.map { $0["name"] as? String } == ["builds"])
  }

  @Test func theTopicsVariableReplacesDiscovery() async {
    var rig = CLIRig(topics: ["alerts"])
    rig.variables["NTFY_TOPICS"] = "one, two"
    let result = await rig.run("subscribe")
    #expect(result.stdout.contains("NTFY_TOPICS environment variable"))
    #expect(result.stdout.contains("  one\n"))
    #expect(!result.stdout.contains("alerts"))
    #expect(await rig.topics.callCount == 0)
  }

  @Test func listingNeedsAConfiguredServer() async {
    let result = await CLIRig(configured: false).run("subscribe")
    #expect(result.exit == .runtime)
    #expect(result.stderr.contains("Run: ntfy-mac setup"))
  }
}
