import NtfyAppLogic
import SwiftUI

/// One message in the log, two lines: the title (bold while unread) with the time, and a
/// preview with the topic. A bar on the leading edge carries the priority of high and urgent
/// messages, a dot marks the unread ones, a check the acknowledged ones.
struct HistoryRowView: View {
  let model: HistoryModel
  let row: MessageRow
  /// The "All messages" log says which topic each message belongs to.
  let showsTopic: Bool
  @State private var hovering = false

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      Circle()
        .fill(row.isRead ? Color.clear : Color.accentColor)
        .frame(width: 7, height: 7)
        .padding(.top, 5)
        .accessibilityLabel(row.isRead ? "" : "Unread")
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 4) {
          if row.isUrgent { PriorityMarker(priority: row.priority).font(.caption) }
          Text(verbatim: row.title)
            .fontWeight(row.isRead ? .regular : .semibold)
            .lineLimit(1)
          Spacer(minLength: 6)
          rowTime
        }
        HStack(spacing: 6) {
          preview
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(1)
          Spacer(minLength: 6)
          if row.isAcknowledged {
            Image(systemName: "checkmark")
              .font(.caption2.weight(.semibold))
              .foregroundStyle(.secondary)
              .help("Acknowledged")
              .accessibilityLabel("Acknowledged")
          }
          if showsTopic {
            Text(verbatim: row.topic)
              .font(.caption)
              .foregroundStyle(.tertiary)
              .lineLimit(1)
              .truncationMode(.middle)
              .frame(maxWidth: 110, alignment: .trailing)
          }
        }
      }
    }
    .padding(.vertical, 5)
    .padding(.leading, 8)
    .padding(.trailing, 10)
    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    .background(hovering ? Color.primary.opacity(0.06) : Color.clear)
    .overlay(alignment: .leading) { priorityBar }
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .accessibilityElement(children: .combine)
  }

  /// High and urgent only; an acknowledged one is dimmed, since nothing is left to do.
  @ViewBuilder private var priorityBar: some View {
    if row.isUrgent {
      Rectangle()
        .fill(row.priority.tint.opacity(row.isAcknowledged ? 0.35 : 1))
        .frame(width: 3)
    }
  }

  @ViewBuilder private var preview: some View {
    if row.isMarkdown {
      Text(MessageBodyRenderer.render(row.preview))
    } else {
      Text(verbatim: row.preview)
    }
  }

  /// "4m ago" within the hour, the clock time after that; the day header carries the date.
  private var rowTime: some View {
    Group {
      if Date().timeIntervalSince(row.time) < 3600 {
        Text(row.time, format: .relative(presentation: .numeric, unitsStyle: .narrow))
      } else {
        Text(row.time.formatted(date: .omitted, time: .shortened))
      }
    }
    .font(.caption)
    .foregroundStyle(row.isRead ? Color.secondary : Color.accentColor)
    .monospacedDigit()
    .lineLimit(1)
    .fixedSize()
  }
}

/// Right-click on a row: copy what it says, open its link, then what can be done to it.
struct HistoryRowMenu: View {
  let model: HistoryModel
  let row: MessageRow
  @Binding var deleting: MessageKey?

  var body: some View {
    Button("Copy Text") { HistoryClipboard.copy(row.body.isEmpty ? row.title : row.body) }
    if row.hasTitle {
      Button("Copy Title") { HistoryClipboard.copy(row.title) }
    }
    if let url = row.clickURL {
      Button("Open Link") { Task { _ = await model.open(url) } }
    }
    Divider()
    if model.canAcknowledge(row) {
      Button("Acknowledge") { Task { await model.acknowledge(row.key) } }
    }
    Button(row.isRead ? "Mark Unread" : "Mark Read") {
      Task {
        if row.isRead {
          await model.markUnread(row.key)
        } else {
          await model.markRead(row.key)
        }
      }
    }
    Menu("Remind Me") {
      ForEach(RemindChoice.allCases, id: \.self) { choice in
        Button(choice.title) { Task { await model.remind(choice, row.key) } }
      }
    }
    Divider()
    Button("Delete…", role: .destructive) { deleting = row.key }
  }
}
