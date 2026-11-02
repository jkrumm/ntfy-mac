import AppKit
import NtfyAppLogic
import UniformTypeIdentifiers

/// The save panels of the History window. Writing happens off the main actor.
@MainActor
enum HistoryFiles {
  /// Asks where to put the export and writes it. Returns normally when the user cancels.
  static func save(_ export: HistoryExport) async throws {
    let type = export.format == .json ? UTType.json : UTType.commaSeparatedText
    guard let url = ask(name: export.suggestedFileName, types: [type]) else { return }
    let data = export.data
    try await Task.detached { try data.write(to: url, options: .atomic) }.value
  }

  /// Asks where to save a copy of a fetched attachment.
  static func saveCopy(of file: URL, named name: String) async throws {
    guard let url = ask(name: name, types: []) else { return }
    try await Task.detached { try SafeFileCopy.copy(file, to: url) }.value
  }

  private static func ask(name: String, types: [UTType]) -> URL? {
    let panel = NSSavePanel()
    panel.nameFieldStringValue = name
    panel.canCreateDirectories = true
    if !types.isEmpty { panel.allowedContentTypes = types }
    return panel.runModal() == .OK ? panel.url : nil
  }
}
