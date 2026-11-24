import Foundation
import NtfyAppLogic
import NtfyCore
import NtfyTesting
import Testing

@MainActor @Suite struct SettingsModelSummaryTests {
  @Test func theEndpointIsNormalizedAndSaved() async {
    let rig = SettingsRig()
    await rig.model.reload()
    rig.model.summaryEndpointText = " https://gw.example.com/anthropic/ "
    await rig.model.commitSummaryEndpoint()
    #expect(await rig.current.summary.endpoint == "https://gw.example.com/anthropic")
    #expect(rig.model.summaryEndpointText == "https://gw.example.com/anthropic")
  }

  @Test func anEmptyEndpointClearsIt() async {
    let rig = SettingsRig()
    await rig.edit { $0.summary.endpoint = "https://gw.example.com" }
    await rig.model.reload()
    rig.model.summaryEndpointText = ""
    await rig.model.commitSummaryEndpoint()
    #expect(await rig.current.summary.endpoint == nil)
  }

  @Test(arguments: ["not a url", "ftp://x.example.com", "http://gw.example.com"])
  func anUnusableEndpointIsRefusedAndNothingIsWritten(text: String) async {
    let rig = SettingsRig()
    await rig.model.reload()
    rig.model.summaryEndpointText = text
    await rig.model.commitSummaryEndpoint()
    #expect(await rig.current.summary.endpoint == nil)
    #expect(rig.model.notice != nil)
  }

  @Test func plainHttpPassesWithTheOptIn() async {
    let rig = SettingsRig()
    await rig.edit { $0.allowInsecure = true }
    await rig.model.reload()
    rig.model.summaryEndpointText = "http://gw.example.com"
    await rig.model.commitSummaryEndpoint()
    #expect(await rig.current.summary.endpoint == "http://gw.example.com")
  }

  @Test func anEmptyModelRestoresTheDefault() async {
    let rig = SettingsRig()
    await rig.edit { $0.summary.model = "haiku" }
    await rig.model.reload()
    rig.model.summaryModelText = " "
    await rig.model.commitSummaryModel()
    #expect(await rig.current.summary.model == SummarySettings.defaultModel)
  }

  @Test func theLimitsAreEnforced() async {
    let rig = SettingsRig()
    await rig.model.reload()
    await rig.model.setSummaryMinMessages(0)
    #expect(await rig.current.summary.minMessages == 3)
    await rig.model.setSummaryMinAwayMinutes(-1)
    #expect(await rig.current.summary.minAwayMinutes == 15)
    #expect(rig.model.notice != nil)
  }

  @Test func theKeyGoesToItsOwnStoreAndNeverToTheFileOrTheToken() async {
    let rig = SettingsRig(token: "tk_old")
    await rig.model.reload()
    rig.model.summaryKeyText = " sk-secret \n"
    await rig.model.saveSummaryKey()
    #expect(await rig.summaryKeys.token() == "sk-secret")
    #expect(await rig.secrets.token() == "tk_old")
    #expect(rig.model.hasSummaryKey)
    #expect(rig.model.summaryKeyText.isEmpty)
    await rig.model.clearSummaryKey()
    #expect(await rig.summaryKeys.token() == nil)
    #expect(!rig.model.hasSummaryKey)
  }

  @Test func theTestSendsOneTinyRequestAndShowsTheAnswer() async {
    let rig = SettingsRig()
    await rig.model.reload()
    await rig.summaryKeys.setToken("door")
    rig.model.summaryEndpointText = "https://gw.example.com/anthropic"
    rig.model.summaryModelText = "haiku"
    await rig.model.testSummary()
    #expect(rig.model.summaryTest == .succeeded("summary"))
    #expect(await rig.summarizer.calls.count == 1)
    #expect(await rig.summarizer.calls.first?.count == 1)
    // What was tested is what is saved.
    #expect(await rig.current.summary.endpoint == "https://gw.example.com/anthropic")
    #expect(await rig.current.summary.model == "haiku")
  }

  @Test func theTestExplainsWhyItFailed() async {
    let rig = SettingsRig()
    await rig.model.reload()
    await rig.summaryKeys.setToken("door")
    rig.model.summaryEndpointText = "https://gw.example.com"
    await rig.summarizer.setOutcome(.failure(.unauthorized))
    await rig.model.testSummary()
    #expect(rig.model.summaryTest == .failed("The endpoint rejected the key."))
  }

  @Test func theTestNeedsAnEndpointAndAKey() async {
    let rig = SettingsRig()
    await rig.model.reload()
    await rig.model.testSummary()
    #expect(rig.model.summaryTest == .failed("Enter an endpoint first."))
    rig.model.summaryEndpointText = "https://gw.example.com"
    await rig.model.testSummary()
    #expect(rig.model.summaryTest == .failed("Store the key first."))
    #expect(await rig.summarizer.calls.isEmpty)
  }

  @Test func theTestSavesATypedKeyFirst() async {
    let rig = SettingsRig()
    await rig.model.reload()
    rig.model.summaryEndpointText = "https://gw.example.com"
    rig.model.summaryKeyText = "sk-typed"
    await rig.model.testSummary()
    #expect(await rig.summaryKeys.token() == "sk-typed")
    #expect(rig.model.summaryTest == .succeeded("summary"))
  }
}
