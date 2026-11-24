import NtfyAppLogic
import SwiftUI

/// The views: "All messages", the messages that wait for an acknowledgement, and one compact row
/// per topic, newest activity first.
struct HistorySidebar: View {
  private enum Item: Hashable {
    case all
    case needsAcknowledgement
    case topic(String)
  }

  @Bindable var model: HistoryModel
  let windows: WindowRouter
  @State private var deleting: Item?
  @State private var emojiTopic: EmojiTarget?

  private struct EmojiTarget: Identifiable {
    let topic: String
    var id: String { topic }
  }

  var body: some View {
    List(selection: selection) {
      row("All messages", symbol: "tray.full", unread: model.totalUnread, urgent: false)
        .tag(Item.all)
        .contextMenu { menu(.all, unread: model.totalUnread) }
      row(
        "Unacknowledged", symbol: "checkmark.circle", unread: model.pendingCount,
        urgent: false, badge: "to acknowledge"
      )
      .tag(Item.needsAcknowledgement)
      .contextMenu { menu(.needsAcknowledgement, unread: 0) }
      if !model.topics.isEmpty {
        Section("Topics") {
          ForEach(model.topics, id: \.topic) { summary in
            row(
              summary.topic, symbol: "number", emoji: model.emoji(for: summary.topic),
              unread: summary.unread,
              urgent: model.urgentTopics.contains(summary.topic)
            )
            .tag(Item.topic(summary.topic))
            .contextMenu { menu(.topic(summary.topic), unread: summary.unread) }
          }
        }
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
    .sheet(item: $emojiTopic) { target in
      TopicEmojiSheet(model: model, topic: target.topic)
    }
  }

  /// Symbol (or the topic's emoji) and name on the left; an urgent marker and the unread count on
  /// the right.
  private func row(
    _ title: String, symbol: String, emoji: String? = nil, unread: Int, urgent: Bool,
    badge: String = "unread"
  ) -> some View {
    HStack(spacing: 6) {
      if let emoji {
        Text(verbatim: emoji)
          .font(.caption)
          .frame(width: 14)
          .accessibilityHidden(true)
      } else {
        Image(systemName: symbol)
          .font(.caption)
          .foregroundStyle(.secondary)
          .frame(width: 14)
          .accessibilityHidden(true)
      }
      Text(verbatim: title)
        .fontWeight(unread > 0 ? .semibold : .regular)
        .lineLimit(1)
        .truncationMode(.middle)
      Spacer(minLength: 4)
      if urgent {
        Image(systemName: "exclamationmark.circle.fill")
          .font(.caption)
          .foregroundStyle(.red)
          .help("Urgent message waiting")
          .accessibilityLabel("Urgent message waiting")
      }
      if unread > 0 {
        Text("\(unread)")
          .font(.caption2.weight(.semibold))
          .monospacedDigit()
          .foregroundStyle(.white)
          .padding(.horizontal, 5)
          .background(Color.accentColor, in: Capsule())
          .accessibilityLabel("\(unread) \(badge)")
      }
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }

  private func menu(_ item: Item, unread: Int) -> some View {
    Group {
      if let topic = name(item) { topicSettingsMenu(topic) }
      Button("Acknowledge All") { Task { await model.acknowledgeAll(topic: name(item)) } }
        .disabled(model.pendingCount(in: scope(of: item)) == 0)
      if item != .needsAcknowledgement {
        Button("Mark All Read") { Task { await model.markAllRead(topic: name(item)) } }
          .disabled(unread == 0)
        Divider()
        Button("Delete All Messages…", role: .destructive) { deleting = item }
      }
    }
  }

  /// Mute, show in All messages, minimum priority, emoji and the Settings window, for one topic.
  @ViewBuilder private func topicSettingsMenu(_ topic: String) -> some View {
    let settings = model.settings(for: topic)
    Toggle(
      "Mute",
      isOn: Binding(
        get: { settings.mute },
        set: { value in Task { await model.setMute(value, topic: topic) } }))
    Toggle(
      "Show in All Messages",
      isOn: Binding(
        get: { !settings.hideFromAll },
        set: { value in Task { await model.setHideFromAll(!value, topic: topic) } }))
    Menu("Minimum Priority") {
      Picker(
        "Minimum Priority",
        selection: Binding(
          get: { settings.minPriority ?? 0 },
          set: { value in
            Task { await model.setMinPriority(value == 0 ? nil : value, topic: topic) }
          })
      ) {
        Text("None").tag(0)
        ForEach(SettingsModel.priorities, id: \.self) { value in
          Text(SettingsModel.priorityTitle(value)).tag(value)
        }
      }
      .pickerStyle(.inline)
    }
    Button("Set Emoji…") { emojiTopic = EmojiTarget(topic: topic) }
    Button("Topic Settings…") { windows.showSettings(section: .topics) }
    Divider()
  }

  private func scope(of item: Item) -> HistoryModel.Scope {
    switch item {
    case .all: .all
    case .needsAcknowledgement: .needsAcknowledgement
    case .topic(let topic): .topic(topic)
    }
  }

  private var selection: Binding<Item?> {
    Binding(
      get: {
        switch model.scope {
        case .all: .all
        case .needsAcknowledgement: .needsAcknowledgement
        case .topic(let topic): .topic(topic)
        }
      },
      set: { item in
        switch item {
        case .all: model.show(.all)
        case .needsAcknowledgement: model.show(.needsAcknowledgement)
        case .topic(let topic): model.show(.topic(topic))
        case nil: break
        }
      })
  }

  /// The topic of a row; nil for the views that span topics.
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
