import NtfyAppLogic
import SwiftUI

/// The middle column: the filters, then the messages as a log grouped by day, or what stands in
/// for it. Up and down move the selection, Return opens the link, Delete asks to remove it.
struct HistoryList: View {
  @Bindable var model: HistoryModel
  @Binding var deleting: MessageKey?

  var body: some View {
    VStack(spacing: 0) {
      HistoryFilterBar(model: model)
      content
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  @ViewBuilder private var content: some View {
    if !model.isAvailable {
      ContentUnavailableView {
        Label("Starting…", systemImage: "hourglass")
      } description: {
        Text("The history is not available yet.")
      }
    } else if model.rows.isEmpty {
      empty
    } else {
      list
    }
  }

  @ViewBuilder private var empty: some View {
    if model.isNarrowing {
      ContentUnavailableView {
        Label("No messages match these filters", systemImage: "line.3.horizontal.decrease")
      } description: {
        Text("Widen the priority or date, or clear the search.")
      } actions: {
        Button("Clear") { model.clearNarrowing() }
      }
    } else {
      ContentUnavailableView(
        "No messages yet", systemImage: "tray",
        description: Text("Messages you receive show up here."))
    }
  }

  private var list: some View {
    List(selection: Binding(get: { model.selection }, set: { model.setSelection($0) })) {
      ForEach(model.days) { group in
        Section {
          ForEach(group.rows) { row in
            HistoryRowView(model: model, row: row, showsTopic: model.selectedTopic == nil)
              .tag(row.key)
              .listRowInsets(EdgeInsets())
              .contextMenu { HistoryRowMenu(model: model, row: row, deleting: $deleting) }
          }
        } header: {
          HistoryDayHeader(group: group)
        }
      }
      if model.hasMore {
        ProgressView()
          .controlSize(.small)
          .frame(maxWidth: .infinity)
          .task { await model.loadMore() }
      }
    }
    .listStyle(.inset)
    .onDeleteCommand { deleting = model.selection }
    .onKeyPress(.return) {
      guard model.detail?.clickURL != nil else { return .ignored }
      Task { _ = await model.openClickURL() }
      return .handled
    }
  }
}

/// A slim day label: Today, Yesterday or the date.
private struct HistoryDayHeader: View {
  let group: DayGroup

  var body: some View {
    Text(verbatim: title)
      .font(.caption.weight(.semibold))
      .foregroundStyle(.secondary)
      .accessibilityAddTraits(.isHeader)
  }

  private var title: String {
    switch group.label(now: Date(), calendar: .current) {
    case .today: "Today"
    case .yesterday: "Yesterday"
    case .date(let day, let includesYear):
      day.formatted(
        includesYear
          ? .dateTime.weekday(.abbreviated).day().month(.abbreviated).year()
          : .dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }
  }
}
