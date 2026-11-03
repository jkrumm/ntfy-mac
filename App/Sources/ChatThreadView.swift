import NtfyAppLogic
import SwiftUI

/// The selected conversation as a thread: day headers that stick, bubbles, a button to jump to
/// the newest message. The list is lazy and pages older messages in from the top.
struct ChatThreadView: View {
  private static let bottomID = "chat-thread-bottom"

  let model: HistoryModel
  @Binding var quickLook: URL?
  @Binding var deleting: MessageKey?
  let report: (String) -> Void

  @State private var atBottom = true
  /// Scroll to the newest message when the next one lands, even if we are not at the bottom
  /// (a new conversation just opened).
  @State private var followNext = true

  var body: some View {
    if !model.isAvailable {
      ContentUnavailableView {
        Label("Starting…", systemImage: "hourglass")
      } description: {
        Text("The history is not available yet.")
      }
    } else if model.thread.isEmpty {
      empty
    } else {
      thread
    }
  }

  @ViewBuilder private var empty: some View {
    if model.isNarrowing {
      ContentUnavailableView {
        Label("No results", systemImage: "magnifyingglass")
      } description: {
        Text("No message matches the current filters.")
      } actions: {
        Button("Clear Filters") { model.clearNarrowing() }
      }
    } else {
      ContentUnavailableView(
        "No messages yet", systemImage: "bubble.left.and.bubble.right",
        description: Text("Messages you receive show up here."))
    }
  }

  private var thread: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(spacing: 10, pinnedViews: [.sectionHeaders]) {
          if model.hasMore {
            ProgressView()
              .controlSize(.small)
              .frame(maxWidth: .infinity)
              .padding(.vertical, 8)
              .task { await loadOlder(proxy) }
          }
          ForEach(model.days) { group in
            Section {
              ForEach(group.messages) { message in
                ChatBubble(
                  model: model, message: message, showsTopic: model.selectedTopic == nil,
                  quickLook: $quickLook, delete: { deleting = $0 }, report: report)
              }
            } header: {
              ChatDayHeader(group: group)
            }
          }
          Color.clear.frame(height: 1).id(Self.bottomID)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
      }
      .id(model.selectedTopic ?? "")
      .defaultScrollAnchor(.bottom)
      .onScrollGeometryChange(for: Bool.self) { geometry in
        geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 48
      } action: { _, nowAtBottom in
        atBottom = nowAtBottom
      }
      .onChange(of: model.thread.last?.id) {
        guard atBottom || followNext else { return }
        followNext = false
        proxy.scrollTo(Self.bottomID, anchor: .bottom)
      }
      .onChange(of: model.selectedTopic) { followNext = true }
      .onChange(of: model.selection) {
        guard let key = model.selection else { return }
        withAnimation { proxy.scrollTo("\(key.topic)/\(key.id)", anchor: .center) }
      }
      .overlay(alignment: .bottomTrailing) {
        if !atBottom { jumpButton(proxy) }
      }
    }
  }

  /// Reads the next older page and keeps the message that was on top where it was.
  private func loadOlder(_ proxy: ScrollViewProxy) async {
    let anchor = model.days.first?.messages.first?.id
    await model.loadMore()
    if let anchor { proxy.scrollTo(anchor, anchor: .top) }
  }

  private func jumpButton(_ proxy: ScrollViewProxy) -> some View {
    let unread =
      model.selectedTopic.flatMap { model.conversation($0)?.unread } ?? model.totalUnread
    return Button {
      withAnimation { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
    } label: {
      HStack(spacing: 6) {
        Image(systemName: "chevron.down")
        if unread > 0 { Text("\(unread)").monospacedDigit() }
      }
      .font(.callout.weight(.semibold))
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.regularMaterial, in: Capsule())
      .overlay(Capsule().strokeBorder(.separator))
    }
    .buttonStyle(.plain)
    .padding(16)
    .help("Jump to newest")
    .accessibilityLabel(unread > 0 ? "Jump to newest, \(unread) unread" : "Jump to newest")
  }
}

/// The day label that sticks to the top while its messages scroll under it.
private struct ChatDayHeader: View {
  let group: DayGroup

  var body: some View {
    Text(verbatim: title)
      .font(.caption.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 10)
      .padding(.vertical, 3)
      .background(.regularMaterial, in: Capsule())
      .frame(maxWidth: .infinity)
      .padding(.vertical, 6)
      .accessibilityAddTraits(.isHeader)
  }

  private var title: String {
    switch group.label(now: Date(), calendar: .current) {
    case .today: "Today"
    case .yesterday: "Yesterday"
    case .date(let day, let includesYear):
      day.formatted(
        includesYear
          ? .dateTime.weekday(.abbreviated).day().month(.wide).year()
          : .dateTime.weekday(.wide).day().month(.wide))
    }
  }
}

/// Who the thread is with and how much there is of it.
struct ChatHeader: View {
  let model: HistoryModel

  var body: some View {
    HStack(spacing: 10) {
      if let topic = model.selectedTopic, let conversation = model.conversation(topic) {
        ChatAvatarView(avatar: conversation.avatar, size: 30)
      } else {
        ChatAllAvatarView(size: 30)
      }
      VStack(alignment: .leading, spacing: 0) {
        Text(verbatim: model.selectedTopic ?? "All")
          .font(.headline)
          .lineLimit(1)
        Text(verbatim: subtitle)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      if model.isNarrowing {
        Button("Clear Filters") { model.clearNarrowing() }
          .controlSize(.small)
      }
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 10)
    .background(.bar)
  }

  private var subtitle: String {
    if model.isNarrowing {
      return model.resultCount == 1 ? "1 result" : "\(model.resultCount) results"
    }
    let total: Int
    let unread: Int
    if let topic = model.selectedTopic {
      total = model.topics.first { $0.topic == topic }?.total ?? 0
      unread = model.conversation(topic)?.unread ?? 0
    } else {
      total = model.totalMessages
      unread = model.totalUnread
    }
    let count = total == 1 ? "1 message" : "\(total) messages"
    return unread > 0 ? "\(count) · \(unread) unread" : count
  }
}
