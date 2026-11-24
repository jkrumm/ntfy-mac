import Foundation
import NtfyCore

private struct MessagesRequest: Encodable {
  struct Turn: Encodable {
    let role: String
    let content: String
  }

  struct Thinking: Encodable { let type: String }

  let model: String
  let maxTokens: Int
  let system: String
  let messages: [Turn]
  /// Set only where thinking would be on by default and `disabled` is accepted.
  let thinking: Thinking?

  private enum CodingKeys: String, CodingKey {
    case model, system, messages, thinking
    case maxTokens = "max_tokens"
  }
}

private struct MessagesReply: Decodable {
  struct Block: Decodable {
    let type: String
    let text: String?
  }

  let content: [Block]
}

private struct APIError: Decodable {
  struct Detail: Decodable { let message: String? }
  let error: Detail?
}

/// `MessageSummarizing` over the Anthropic Messages API: one non-streamed `POST <endpoint>/v1/messages`.
///
/// The endpoint is a base URL, so it works against `https://api.anthropic.com` and against any
/// gateway that speaks the same protocol under a prefix. The key travels in `x-api-key` (a gateway's
/// door token goes in the same header) and only over https, a loopback host or an explicit
/// `allowInsecure`; redirects are never followed.
public struct AnthropicSummarizer: MessageSummarizing {
  public static let apiVersion = "2023-06-01"
  /// Room for a short summary with a model that thinks first: a smaller limit can leave no text.
  public static let maxTokens = 1024
  public static let timeout: TimeInterval = 20

  private let endpoint: URL
  private let apiKey: String
  private let model: String
  private let allowInsecure: Bool
  private let timeout: TimeInterval
  private let session: URLSession

  public init(
    endpoint: URL, apiKey: String, model: String, allowInsecure: Bool = false,
    timeout: TimeInterval = AnthropicSummarizer.timeout,
    session: URLSession = URLSession(configuration: .ephemeral)
  ) {
    self.endpoint = endpoint
    self.apiKey = apiKey
    self.model = model
    self.allowInsecure = allowInsecure
    self.timeout = timeout
    self.session = session
  }

  /// The summarizer for the config strings, nil when the endpoint is not a usable address.
  public static func make(
    endpoint: String, key: String, model: String, allowInsecure: Bool
  ) -> AnthropicSummarizer? {
    guard let normalized = SummaryEndpoint.normalized(endpoint), let url = URL(string: normalized)
    else { return nil }
    return AnthropicSummarizer(
      endpoint: url, apiKey: key, model: model, allowInsecure: allowInsecure)
  }

  public func summarize(_ entries: [DigestEntry]) async throws(NtfyError) -> String {
    let url = try ServerEndpoint.url(
      base: endpoint, path: "v1/messages", token: apiKey, allowInsecure: allowInsecure)
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.timeoutInterval = timeout
    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try Self.body(model: model, entries: entries)
    let data: Data
    do {
      let (body, response) = try await session.data(for: request, delegate: RedirectRefuser())
      try Self.validate(response, body: body, requested: url)
      data = body
    } catch {
      throw ServerResponse.error(from: error)
    }
    guard let reply = try? JSONDecoder().decode(MessagesReply.self, from: data) else {
      throw .invalidResponse("undecodable response")
    }
    let text = reply.content.filter { $0.type == "text" }.compactMap(\.text).joined(
      separator: "\n")
    guard !text.isEmpty else { throw .invalidResponse("no text in the response") }
    return text
  }

  /// Haiku 5.x thinks when `thinking` is absent, which only costs time and tokens for a three-line
  /// summary, and accepts `disabled`; other models are left at their own default (Sonnet 5.x
  /// rejects `disabled`).
  static func switchesThinkingOff(_ model: String) -> Bool {
    let name = model.lowercased()
    return name == "haiku" || name.contains("haiku-5")
  }

  private static func body(model: String, entries: [DigestEntry]) throws(NtfyError) -> Data {
    let body = MessagesRequest(
      model: model, maxTokens: maxTokens, system: SummaryPrompt.system,
      messages: [.init(role: "user", content: SummaryPrompt.content(for: entries))],
      thinking: switchesThinkingOff(model) ? .init(type: "disabled") : nil)
    do {
      return try JSONEncoder().encode(body)
    } catch {
      throw .invalidResponse("unencodable request")
    }
  }

  /// The shared status rules, except that a 4xx names its reason: the user fixes the model name or
  /// the request size from it.
  private static func validate(
    _ response: URLResponse, body: Data, requested: URL
  ) throws(NtfyError) {
    if let http = response as? HTTPURLResponse, (400..<500).contains(http.statusCode),
      ![401, 403, 429].contains(http.statusCode)
    {
      let message = (try? JSONDecoder().decode(APIError.self, from: body))?.error?.message
      let reason = message.map { String($0.prefix(200)) }
      throw .invalidResponse("HTTP \(http.statusCode)" + (reason.map { ": \($0)" } ?? ""))
    }
    try ServerResponse.validate(response, requested: requested)
  }
}
