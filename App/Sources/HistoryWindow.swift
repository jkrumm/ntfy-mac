import AppKit
import NtfyAppLogic
import NtfyCore
import SwiftUI

/// The History window, a notification log: topics on the left, the messages of the selected one
/// in the middle under their filters, the selected message in full on the right. The model is
/// built by the app delegate; the window runs it while it is open.
struct HistoryWindow: View {
  @Bindable var model: HistoryModel
  let windows: WindowRouter
  @State private var deleting: MessageKey?
  @State private var quickLook: URL?
  @State private var notice: String?

  var body: some View {
    NavigationSplitView {
      HistorySidebar(model: model)
        .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
    } content: {
      HistoryList(model: model, deleting: $deleting)
        .navigationSplitViewColumnWidth(min: 300, ideal: 370, max: 440)
    } detail: {
      detail
    }
    .searchable(text: $model.searchText, placement: .toolbar, prompt: "Search messages")
    .toolbar { HistoryToolbar(model: model, export: export) }
    .toolbar(removing: .title)
    .frame(
      minWidth: CGFloat(AppWindow.history.minimumSize.width),
      minHeight: CGFloat(AppWindow.history.minimumSize.height)
    )
    .fileQuickLook($quickLook)
    .environment(\.openURL, OpenURLAction(handler: Self.open))
    .confirmationDialog(
      "Delete this message?",
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        if let key = deleting { Task { await model.delete(key) } }
        deleting = nil
      }
    } message: {
      Text("This cannot be undone.")
    }
    .alert(
      "Something went wrong",
      isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })
    ) {
      Button("OK") { notice = nil }
    } message: {
      Text(verbatim: notice ?? "")
    }
    .onAppear {
      if model.publisher == nil { model.publisher = ConfiguredPublisherProvider.live() }
      model.start()
      applyPendingSelection()
    }
    .onDisappear { model.stop() }
    .onChange(of: windows.pendingSelection) { applyPendingSelection() }
    .onChange(of: model.isAvailable) { applyPendingSelection() }
  }

  @ViewBuilder private var detail: some View {
    if let shown = model.detail {
      HistoryDetail(
        model: model, detail: shown, quickLook: $quickLook, deleting: $deleting,
        report: { notice = $0 })
    } else {
      ContentUnavailableView(
        "No message selected", systemImage: "tray",
        description: Text("Pick a message to read it here."))
    }
  }

  /// Applies the router's selection once the history is readable, and clears it.
  private func applyPendingSelection() {
    guard model.isAvailable, let key = windows.takeSelection() else { return }
    Task { await model.apply(selection: key) }
  }

  private func export(_ format: ExportFormat) {
    Task {
      do {
        guard let result = try await model.export(format) else {
          notice = "There are no messages to export for the current filters."
          return
        }
        try await HistoryFiles.save(result)
      } catch {
        notice = "The export failed: \(error.localizedDescription)"
      }
    }
  }

  /// Only http, https and mailto links open, and they open in the default app.
  private static func open(_ url: URL) -> OpenURLAction.Result {
    guard let allowed = URLPolicy.openable(url) else { return .discarded }
    NSWorkspace.shared.open(allowed)
    return .handled
  }
}
