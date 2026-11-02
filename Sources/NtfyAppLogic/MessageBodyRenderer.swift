import Foundation
import NtfyCore

/// Turns a markdown message body into text the detail pane can show. `Text` renders inline
/// markdown only, so list markers become bullets here, and a link survives only when its target
/// may be opened (`URLPolicy.openable`: http, https, mailto).
public enum MessageBodyRenderer {
  /// The styled body; the plain string when the markdown does not parse.
  public static func render(_ body: String) -> AttributedString {
    let options = AttributedString.MarkdownParsingOptions(
      interpretedSyntax: .inlineOnlyPreservingWhitespace)
    guard
      let parsed = try? AttributedString(markdown: normaliseListMarkers(body), options: options)
    else { return AttributedString(body) }
    return strippingUnsafeLinks(parsed)
  }

  /// `-`, `*` and `+` followed by a space at the start of a line (after any indent) become `•`.
  static func normaliseListMarkers(_ text: String) -> String {
    text.split(separator: "\n", omittingEmptySubsequences: false)
      .map(bulleted)
      .joined(separator: "\n")
  }

  /// The text without the `link` attribute on every run whose URL is not openable.
  static func strippingUnsafeLinks(_ text: AttributedString) -> AttributedString {
    var result = text
    let unsafe = text.runs.compactMap { run -> Range<AttributedString.Index>? in
      guard let url = run.link, URLPolicy.openable(url) == nil else { return nil }
      return run.range
    }
    for range in unsafe { result[range].link = nil }
    return result
  }

  private static func bulleted(_ line: Substring) -> String {
    let indent = line.prefix { $0 == " " || $0 == "\t" }
    let rest = line.dropFirst(indent.count)
    guard let marker = rest.first, "-*+".contains(marker), rest.dropFirst().first == " " else {
      return String(line)
    }
    return indent + "•" + rest.dropFirst()
  }
}
