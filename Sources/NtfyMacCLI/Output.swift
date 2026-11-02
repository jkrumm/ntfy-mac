import Foundation

/// The CLI's two channels. Data goes to stdout, diagnostics, progress and prompts to stderr.
/// In `--json` mode stdout carries JSON documents and nothing else: exactly one for a command,
/// one per line (NDJSON) for a streaming command.
struct Output: Sendable {
  let json: Bool
  private let writeStdout: @Sendable (String) -> Void
  private let writeStderr: @Sendable (String) -> Void

  init(
    json: Bool, stdout: @escaping @Sendable (String) -> Void,
    stderr: @escaping @Sendable (String) -> Void
  ) {
    self.json = json
    writeStdout = stdout
    writeStderr = stderr
  }

  /// The process's real stdout and stderr.
  static func standard(json: Bool) -> Output {
    Output(
      json: json,
      stdout: { FileHandle.standardOutput.write(Data($0.utf8)) },
      stderr: { FileHandle.standardError.write(Data($0.utf8)) })
  }

  /// A line of data for people; silent in `--json` mode.
  func line(_ text: String = "") {
    guard !json else { return }
    writeStdout(text + "\n")
  }

  /// Text written to stdout in either mode (help output).
  func raw(_ text: String) {
    writeStdout(text.hasSuffix("\n") ? text : text + "\n")
  }

  /// A diagnostic line on stderr: progress, hints, warnings.
  func note(_ text: String) {
    writeStderr(text + "\n")
  }

  /// One JSON document on its own line; silent in text mode.
  func document<Value: Encodable>(_ value: Value) {
    guard json, let text = Self.encode(value) else { return }
    writeStdout(text + "\n")
  }

  /// The command's result: the JSON document, or the text lines.
  func result<Value: Encodable>(_ value: Value, text: @autoclosure () -> String) {
    if json {
      document(value)
    } else {
      line(text())
    }
  }

  /// Reports a failure: the envelope on stdout in `--json` mode, the human line on stderr always.
  func fail(_ report: ErrorReport) {
    document(ErrorEnvelope(error: report))
    note("Error: \(report.message)")
  }

  private static func encode<Value: Encodable>(_ value: Value) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .iso8601
    return (try? encoder.encode(value)).flatMap { String(bytes: $0, encoding: .utf8) }
  }
}
