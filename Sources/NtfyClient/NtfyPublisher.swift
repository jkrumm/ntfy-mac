import Foundation
import NtfyCore

private struct PublishBody: Encodable {
  let topic: String
  let message: String
  let title: String?
  let priority: Int?
  let tags: [String]?
  let click: String?
}

private struct PublishReply: Decodable {
  let id: String
  let topic: String?
  let time: TimeInterval?
}

/// `NtfyPublishing` backed by a JSON `POST` to the server root. The token travels only over
/// https, a loopback host or an explicit `allowInsecure`; redirects are never followed.
public struct NtfyPublisher: NtfyPublishing {
  private let base: URL
  private let token: String
  private let allowInsecure: Bool
  private let timeout: TimeInterval
  private let session: URLSession

  public init(
    base: URL, token: String, allowInsecure: Bool = false, timeout: TimeInterval = 15,
    session: URLSession = URLSession(configuration: .ephemeral)
  ) {
    self.base = base
    self.token = token
    self.allowInsecure = allowInsecure
    self.timeout = timeout
    self.session = session
  }

  public func publish(_ request: PublishRequest) async throws(NtfyError) -> PublishedMessage {
    guard TopicResolver.isValid(request.topic) else { throw .invalidTopic(request.topic) }
    let url = try ServerEndpoint.url(
      base: base, path: "", token: token, allowInsecure: allowInsecure)
    var urlRequest = URLRequest.authorized(url, token: token, timeout: timeout)
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    urlRequest.httpBody = try Self.body(request)
    let data: Data
    do {
      let (body, response) = try await session.data(for: urlRequest, delegate: RedirectRefuser())
      try ServerResponse.validate(response, requested: url)
      data = body
    } catch {
      throw ServerResponse.error(from: error)
    }
    guard let reply = try? JSONDecoder().decode(PublishReply.self, from: data) else {
      throw .invalidResponse("undecodable publish response")
    }
    return PublishedMessage(
      id: reply.id, topic: reply.topic ?? request.topic,
      time: reply.time.map { Date(timeIntervalSince1970: $0) } ?? Date())
  }

  private static func body(_ request: PublishRequest) throws(NtfyError) -> Data {
    let body = PublishBody(
      topic: request.topic, message: request.message, title: request.title,
      priority: request.priority?.rawValue, tags: request.tags.isEmpty ? nil : request.tags,
      click: request.click?.absoluteString)
    do {
      return try JSONEncoder().encode(body)
    } catch {
      throw .invalidResponse("cannot encode the message")
    }
  }
}
