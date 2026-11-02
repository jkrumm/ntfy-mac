import NtfyAppLogic
import NtfyCore
import SwiftUI

/// The window toolbar: one filter menu and export. Search is `.searchable` on the window.
struct HistoryFilterBar: ToolbarContent {
  @Bindable var model: HistoryModel
  let export: (ExportFormat) -> Void

  var body: some ToolbarContent {
    ToolbarItemGroup {
      Menu {
        Picker("Priority", selection: $model.minPriority) {
          Text("Any priority").tag(Priority?.none)
          ForEach([Priority.low, .default, .high, .max], id: \.self) { priority in
            Text(priority == .max ? "Urgent only" : "\(priority.name) and up").tag(
              Priority?.some(priority))
          }
        }
        .pickerStyle(.inline)
        Picker("Date", selection: $model.dateFilter) {
          ForEach(HistoryDateFilter.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.inline)
        Toggle("Unread only", isOn: $model.unreadOnly)
        if model.isNarrowing {
          Divider()
          Button("Clear Filters") { model.clearNarrowing() }
        }
      } label: {
        Label(
          "Filter",
          systemImage: model.isNarrowing
            ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
      }
      .help("Filter by priority, date or unread")

      Menu {
        Button("Export as JSON…") { export(.json) }
        Button("Export as CSV…") { export(.csv) }
      } label: {
        Label("Export", systemImage: "square.and.arrow.up")
      }
      .help("Export the messages matching the filters")
      .accessibilityLabel("Export")
    }
  }
}
