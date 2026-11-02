import NtfyAppLogic
import SwiftUI

/// The message list, or what stands in for it.
struct HistoryList: View {
  let model: HistoryModel
  @Binding var confirmingDelete: Bool
  /// Space opens Quick Look for a ready attachment.
  let quickLook: () -> Bool

  var body: some View {
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
    if model.isFiltering {
      ContentUnavailableView {
        Label("No results", systemImage: "magnifyingglass")
      } description: {
        Text("No message matches the current filters.")
      } actions: {
        Button("Clear Filters") { model.resetFilters() }
      }
    } else {
      ContentUnavailableView(
        "No messages yet", systemImage: "tray",
        description: Text("Messages you receive show up here."))
    }
  }

  private var list: some View {
    List(selection: Binding(get: { model.selection }, set: { model.setSelection($0) })) {
      ForEach(model.rows) { row in
        HistoryRowView(row: row).tag(row.key)
      }
      if model.hasMore {
        ProgressView()
          .frame(maxWidth: .infinity)
          .task { await model.loadMore() }
      }
    }
    .onDeleteCommand { if model.selection != nil { confirmingDelete = true } }
    .onKeyPress(.space) { quickLook() ? .handled : .ignored }
  }
}

private struct HistoryRowView: View {
  let row: MessageRow

  var body: some View {
    HStack(alignment: .top, spacing: 8) {
      Circle()
        .fill(row.isRead ? Color.clear : Color.accentColor)
        .frame(width: 8, height: 8)
        .padding(.top, 5)
        .accessibilityLabel(row.isRead ? "" : "Unread")
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 4) {
          Text(verbatim: row.title)
            .fontWeight(row.isRead ? .regular : .semibold)
            .lineLimit(1)
          Spacer(minLength: 4)
          PriorityMarker(priority: row.priority)
          if row.isAcknowledged {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
              .accessibilityLabel("Acknowledged")
          }
          Text(row.time.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated)))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        Text(verbatim: row.body)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(2)
        Text(verbatim: row.topic)
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
    .padding(.vertical, 2)
    .accessibilityElement(children: .combine)
  }
}
