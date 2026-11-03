import NtfyAppLogic
import SwiftUI

/// The conversations: "All" and one row per topic, newest activity first.
struct HistorySidebar: View {
  private enum Item: Hashable {
    case all
    case topic(String)
  }

  @Bindable var model: HistoryModel
  @State private var deleting: Item?

  var body: some View {
    List(selection: selection) {
      allRow.tag(Item.all)
      ForEach(model.conversations) { conversation in
        ConversationRow(conversation: conversation)
          .tag(Item.topic(conversation.topic))
          .contextMenu { menu(.topic(conversation.topic), unread: conversation.unread) }
      }
    }
    .listStyle(.sidebar)
    .confirmationDialog(
      deleting.map(prompt) ?? "",
      isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete All Messages", role: .destructive) {
        if let item = deleting { Task { await delete(item) } }
        deleting = nil
      }
    } message: {
      Text("This cannot be undone.")
    }
  }

  private var allRow: some View {
    let newest = model.conversations.first
    return ConversationRowLayout(
      avatar: { ChatAllAvatarView() }, title: "All", time: newest?.time,
      preview: newest.map { "\($0.topic): \($0.preview)" } ?? "No messages yet",
      unread: model.totalUnread, hasUrgent: model.conversations.contains(where: \.hasUrgent)
    )
    .contextMenu { menu(.all, unread: model.totalUnread) }
  }

  private func menu(_ item: Item, unread: Int) -> some View {
    Group {
      Button("Mark All Read") { Task { await model.markAllRead(topic: name(item)) } }
        .disabled(unread == 0)
      Divider()
      Button("Delete All Messages…", role: .destructive) { deleting = item }
    }
  }

  private var selection: Binding<Item?> {
    Binding(
      get: { model.selectedTopic.map(Item.topic) ?? .all },
      set: { item in
        guard let item else { return }
        model.selectedTopic = name(item)
      })
  }

  private func name(_ item: Item) -> String? {
    if case .topic(let name) = item { name } else { nil }
  }

  private func prompt(_ item: Item) -> String {
    name(item).map { "Delete all messages in \($0)?" } ?? "Delete all messages in every topic?"
  }

  private func delete(_ item: Item) async {
    if let topic = name(item) {
      await model.deleteAll(topic: topic)
      return
    }
    for summary in model.topics { await model.deleteAll(topic: summary.topic) }
  }
}

private struct ConversationRow: View {
  let conversation: Conversation

  var body: some View {
    ConversationRowLayout(
      avatar: { ChatAvatarView(avatar: conversation.avatar) }, title: conversation.topic,
      time: conversation.time, preview: conversation.preview, unread: conversation.unread,
      hasUrgent: conversation.hasUrgent)
  }
}

/// Avatar, name and one-line preview on the left; time, unread badge and urgent marker on the right.
private struct ConversationRowLayout<Avatar: View>: View {
  @ViewBuilder let avatar: () -> Avatar
  let title: String
  let time: Date?
  let preview: String
  let unread: Int
  let hasUrgent: Bool

  var body: some View {
    HStack(spacing: 10) {
      avatar()
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: title)
          .fontWeight(unread > 0 ? .semibold : .medium)
          .lineLimit(1)
        Text(verbatim: preview)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      VStack(alignment: .trailing, spacing: 4) {
        if let time {
          ChatTimeText(time: time)
            .font(.caption)
            .foregroundStyle(unread > 0 ? Color.accentColor : Color.secondary)
        }
        HStack(spacing: 4) {
          if hasUrgent {
            Image(systemName: "exclamationmark.circle.fill")
              .foregroundStyle(.red)
              .help("Urgent message waiting")
              .accessibilityLabel("Urgent message waiting")
          }
          if unread > 0 {
            Text("\(unread)")
              .font(.caption2.weight(.semibold))
              .monospacedDigit()
              .foregroundStyle(.white)
              .padding(.horizontal, 6)
              .padding(.vertical, 1)
              .background(Color.accentColor, in: Capsule())
              .accessibilityLabel("\(unread) unread")
          }
        }
        .frame(height: 16)
      }
    }
    .padding(.vertical, 4)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

/// Today as a clock time, yesterday by name, older days as a short date.
struct ChatTimeText: View {
  let time: Date

  var body: some View {
    let calendar = Calendar.current
    if calendar.isDateInToday(time) {
      Text(time.formatted(date: .omitted, time: .shortened))
    } else if calendar.isDateInYesterday(time) {
      Text("Yesterday")
    } else {
      Text(time.formatted(.dateTime.day().month(.abbreviated)))
    }
  }
}
