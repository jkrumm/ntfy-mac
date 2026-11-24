import Foundation

/// The one Copy of a message, for the detail bar and the row menu.
enum MessageCopy {
  /// Title and body with a blank line between; whichever is blank is left out.
  static func text(title: String, body: String) -> String {
    [title, body]
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
      .joined(separator: "\n\n")
  }
}
