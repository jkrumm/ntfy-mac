import NtfyCore

/// A summarizer that answers with a fixed text, or fails, and remembers what it was asked.
public actor ScriptedSummarizer: MessageSummarizing {
  public private(set) var calls: [[DigestEntry]] = []
  private var outcome: Result<String, NtfyError>

  public init(_ outcome: Result<String, NtfyError> = .success("summary")) {
    self.outcome = outcome
  }

  public func setOutcome(_ outcome: Result<String, NtfyError>) {
    self.outcome = outcome
  }

  public func summarize(_ entries: [DigestEntry]) throws(NtfyError) -> String {
    calls.append(entries)
    return try outcome.get()
  }
}
