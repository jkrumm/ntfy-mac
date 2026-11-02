import NtfyCore

/// Answers each poll with the next scripted response, then with an empty list.
public actor ScriptedMessagePoller: MessagePoller {
  public enum Response: Sendable {
    case messages([NtfyMessage])
    case fail(NtfyError)
  }

  public struct Call: Sendable, Hashable {
    public let topics: [String]
    public let since: String?
  }

  public private(set) var calls: [Call] = []
  private var responses: [Response]

  public init(_ responses: [Response] = []) {
    self.responses = responses
  }

  public func poll(topics: [String], since: String?) throws(NtfyError) -> [NtfyMessage] {
    calls.append(Call(topics: topics, since: since))
    guard !responses.isEmpty else { return [] }
    switch responses.removeFirst() {
    case .messages(let messages): return messages
    case .fail(let error): throw error
    }
  }
}
