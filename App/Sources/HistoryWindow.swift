import NtfyAppLogic
import SwiftUI

/// Placeholder: the History window task replaces this body and owns the file.
struct HistoryWindow: View {
  let model: AppModel
  let windows: WindowRouter

  var body: some View {
    Text(windows.pendingSelection.map { "Selected: \($0.topic)/\($0.id)" } ?? "History")
      .frame(minWidth: 480, minHeight: 320)
  }
}
