import Foundation
import NtfyCore

/// The Test button of the away digest.
public enum SummaryTestState: Sendable, Hashable {
  case idle
  case testing
  /// The endpoint answered; the model's reply, shortened.
  case succeeded(String)
  case failed(String)

  public var isTesting: Bool { self == .testing }
}

extension SettingsModel {
  // MARK: Away digest

  public func setSummaryEnabled(_ enabled: Bool) async {
    await write { $0.summary.enabled = enabled }
  }

  /// Saves the typed endpoint; an empty one clears it. Refused: something that is not an http(s)
  /// URL, and plain http without `allowInsecure`, as the CLI does.
  public func commitSummaryEndpoint() async {
    let typed = summaryEndpointText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !typed.isEmpty else {
      await write { $0.summary.endpoint = nil }
      return
    }
    guard let endpoint = SummaryEndpoint.normalized(typed) else {
      refuse("The endpoint must be an http(s) address such as https://api.anthropic.com.")
      return
    }
    guard SummaryEndpoint.isSecure(endpoint, allowInsecure: config.allowInsecure) else {
      refuse("A plain http endpoint would send the key unprotected. Use https.")
      return
    }
    summaryEndpointText = endpoint
    await write { $0.summary.endpoint = endpoint }
  }

  /// Saves the typed model; an empty one restores the default.
  public func commitSummaryModel() async {
    let typed = summaryModelText.trimmingCharacters(in: .whitespacesAndNewlines)
    let model = typed.isEmpty ? SummarySettings.defaultModel : typed
    summaryModelText = model
    await write { $0.summary.model = model }
  }

  public func setSummaryMinAwayMinutes(_ minutes: Int) async {
    guard minutes >= 0 else {
      refuse("The minutes away must be 0 or more.")
      return
    }
    await write { $0.summary.minAwayMinutes = minutes }
  }

  public func setSummaryMinMessages(_ count: Int) async {
    guard count > 0 else {
      refuse("The number of messages must be above 0.")
      return
    }
    await write { $0.summary.minMessages = count }
  }

  /// Stores the typed key in the Keychain.
  public func saveSummaryKey() async {
    let key = summaryKeyText.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !key.isEmpty else { return }
    do throws(NtfyError) {
      try await summaryKeys.setToken(key)
      summaryKeyText = ""
      hasSummaryKey = true
      notice = nil
    } catch {
      notice = "The key could not be saved: \(error)"
    }
  }

  public func clearSummaryKey() async {
    do throws(NtfyError) {
      try await summaryKeys.deleteToken()
      hasSummaryKey = false
      notice = nil
    } catch {
      notice = "The key could not be removed: \(error)"
    }
  }

  /// One tiny request with the typed endpoint and model and the stored key; the answer, or why
  /// there was none, goes to `summaryTest`.
  public func testSummary() async {
    guard !summaryTest.isTesting else { return }
    summaryTest = .testing
    await commitSummaryEndpoint()
    await commitSummaryModel()
    guard let endpoint = config.summary.endpoint else {
      summaryTest = .failed("Enter an endpoint first.")
      return
    }
    if !summaryKeyText.isEmpty { await saveSummaryKey() }
    guard
      let summarizer = await summarizers.summarizer(
        endpoint: endpoint, model: config.summary.model, allowInsecure: config.allowInsecure)
    else {
      summaryTest = .failed("Store the key first.")
      return
    }
    let sample = DigestEntry(
      topic: "test", priority: 3, time: app.clock.now(), title: "Test",
      body: "ntfy-mac checks that the summary endpoint answers.")
    do throws(NtfyError) {
      let reply = try await summarizer.summarize([sample])
      summaryTest = .succeeded(String(reply.prefix(120)))
    } catch {
      summaryTest = .failed(Self.explanation(of: error))
    }
  }

  static func explanation(of error: NtfyError) -> String {
    switch error {
    case .unauthorized: "The endpoint rejected the key."
    case .serverUnreachable: "The endpoint did not answer in time, or answered with a server error."
    case .rateLimited: "The endpoint is limiting requests; try again in a minute."
    case .redirected: "The endpoint redirected; the key is never sent to another address."
    case .insecureServer: "A plain http endpoint would send the key unprotected."
    case .invalidResponse(let detail): "Unexpected answer: \(detail)"
    case .invalidTopic, .appUnavailable, .permissionDenied, .storage: "The test failed: \(error)."
    }
  }
}
