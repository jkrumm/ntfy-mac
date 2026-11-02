import NtfyAppLogic
import NtfyCore
import SwiftUI

/// The window toolbar: filters, the result count and export. Search is `.searchable` on the window.
struct HistoryFilterBar: ToolbarContent {
  @Bindable var model: HistoryModel
  let export: (ExportFormat) -> Void

  var body: some ToolbarContent {
    ToolbarItemGroup {
      Picker("Priority", selection: $model.minPriority) {
        Text("Any priority").tag(Priority?.none)
        ForEach([Priority.low, .default, .high, .max], id: \.self) { priority in
          Text(priority == .max ? "Urgent only" : "\(priority.name) and up").tag(
            Priority?.some(priority))
        }
      }
      .help("Show only messages at or above a priority")

      Picker("Date", selection: $model.dateFilter) {
        ForEach(HistoryDateFilter.allCases, id: \.self) { Text($0.title).tag($0) }
      }
      .help("Show only recent messages")

      Toggle(isOn: $model.unreadOnly) {
        Label("Unread only", systemImage: "envelope.badge")
      }
      .help("Show only unread messages")

      Text(model.resultCount == 1 ? "1 result" : "\(model.resultCount) results")
        .font(.callout)
        .foregroundStyle(.secondary)
        .monospacedDigit()

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
