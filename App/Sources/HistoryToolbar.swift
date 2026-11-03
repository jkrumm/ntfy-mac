import NtfyAppLogic
import NtfyCore
import SwiftUI

/// The window toolbar: a new message and export. Search is `.searchable` on the window; the
/// filters live above the list.
struct HistoryToolbar: ToolbarContent {
  let model: HistoryModel
  let export: (ExportFormat) -> Void
  @State private var composing = false

  var body: some ToolbarContent {
    ToolbarItemGroup {
      Button {
        model.openComposer()
        composing = true
      } label: {
        Label("New Message…", systemImage: "square.and.pencil")
      }
      .help("Send a new message")
      .popover(isPresented: $composing, arrowEdge: .bottom) {
        HistoryNewMessage(model: model) { composing = false }
      }

      Menu {
        Button("Export as JSON…") { export(.json) }
        Button("Export as CSV…") { export(.csv) }
      } label: {
        Label("Export", systemImage: "square.and.arrow.up")
      }
      .help("Export the messages matching the filters")
    }
  }
}
