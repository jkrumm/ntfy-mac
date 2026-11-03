import AppKit

/// Plain text onto the general pasteboard, for the Copy actions of the History window.
enum HistoryClipboard {
  static func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
}
