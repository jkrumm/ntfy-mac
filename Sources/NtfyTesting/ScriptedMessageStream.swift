import NtfyCore

/// Replays a fixed script, then finishes (or fails with the scripted error).
public struct ScriptedMessageStream: MessageStream {
  public enum Step: Sendable {
    case message(NtfyMessage)
    case fail(NtfyError)
  }

  private let script: [Step]

  public init(_ script: [Step]) {
    self.script = script
  }

  public func messages(
    topics: [String], since: String?
  ) -> AsyncThrowingStream<NtfyMessage, any Error> {
    AsyncThrowingStream(NtfyMessage.self, bufferingPolicy: .unbounded) { continuation in
      for step in script {
        switch step {
        case .message(let message):
          continuation.yield(message)
        case .fail(let error):
          continuation.finish(throwing: error)
          return
        }
      }
      continuation.finish()
    }
  }
}
