import NtfyCore

/// Answers every connection test with a fixed result and remembers what it was asked.
public actor ScriptedServerTester: ServerTesting {
  public struct Call: Sendable, Hashable {
    public let url: String
    public let token: String
    public let allowInsecure: Bool

    public init(url: String, token: String, allowInsecure: Bool) {
      self.url = url
      self.token = token
      self.allowInsecure = allowInsecure
    }
  }

  public private(set) var calls: [Call] = []
  private var result: ServerTestResult

  public init(_ result: ServerTestResult = .ok(topics: [])) {
    self.result = result
  }

  public func setResult(_ result: ServerTestResult) {
    self.result = result
  }

  public func test(url: String, token: String, allowInsecure: Bool) -> ServerTestResult {
    calls.append(Call(url: url, token: token, allowInsecure: allowInsecure))
    return result
  }
}
