import ArgumentParser
import Foundation
import NtfyCore

/// What `wait --match` looks for in a message's title and text: a substring (case-insensitive)
/// or, written as `/pattern/`, a regular expression whose `^` and `$` match at line ends (add `i`
/// after the closing slash to ignore case).
struct MessageMatcher: Sendable {
  private enum Rule: Sendable {
    case substring(String)
    case pattern(NSRegularExpression)
  }

  private let rule: Rule

  /// - Throws: `ValidationError` when the text is empty or its pattern does not compile.
  init(_ text: String) throws {
    guard !text.isEmpty else { throw ValidationError("--match must not be empty.") }
    guard let (source, ignoreCase) = Self.patternParts(text) else {
      rule = .substring(text)
      return
    }
    do {
      var options: NSRegularExpression.Options = [.anchorsMatchLines]
      if ignoreCase { options.insert(.caseInsensitive) }
      rule = .pattern(try NSRegularExpression(pattern: source, options: options))
    } catch {
      throw ValidationError("--match is not a valid regular expression: \(source)")
    }
  }

  /// `/source/` or `/source/i`; anything else (a path such as `/usr/bin`) is a plain substring.
  private static func patternParts(_ text: String) -> (String, Bool)? {
    guard text.first == "/", let slash = text.dropFirst().lastIndex(of: "/") else { return nil }
    let flags = text[text.index(after: slash)...]
    let source = String(text[text.index(after: text.startIndex)..<slash])
    guard !source.isEmpty, flags.isEmpty || flags == "i" else { return nil }
    return (source, flags == "i")
  }

  func matches(_ message: NtfyMessage) -> Bool {
    let haystack = [message.title, message.body].compactMap { $0 }.joined(separator: "\n")
    switch rule {
    case .substring(let needle):
      return haystack.localizedCaseInsensitiveContains(needle)
    case .pattern(let expression):
      let range = NSRange(haystack.startIndex..., in: haystack)
      return expression.firstMatch(in: haystack, range: range) != nil
    }
  }
}
