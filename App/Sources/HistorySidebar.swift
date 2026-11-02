import NtfyAppLogic
import NtfyCore
import SwiftUI

/// "All messages" and every topic with its unread count.
struct HistorySidebar: View {
  private enum Item: Hashable {
    case all
    case topic(String)
  }

  @Bindable var model: HistoryModel
  @State private var deleting: Item?

  var body: some View {
    List(selection: selection) {
      row(.all, title: "All messages", symbol: "tray.full", unread: model.totalUnread)
      Section("Topics") {
        ForEach(model.topics) { topic in
          row(.topic(topic.topic), title: topic.topic, symbol: "number", unread: topic.unread)
        }
      }
    }
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

  private var selection: Binding<Item?> {
    Binding(
      get: { model.selectedTopic.map(Item.topic) ?? .all },
      set: { item in
        guard let item else { return }
        if case .topic(let name) = item {
          model.selectedTopic = name
        } else {
          model.selectedTopic = nil
        }
      })
  }

  private func row(_ item: Item, title: String, symbol: String, unread: Int) -> some View {
    Label(title, systemImage: symbol)
      .badge(unread)
      .tag(item)
      .contextMenu {
        Button("Mark All Read") { Task { await model.markAllRead(topic: name(item)) } }
          .disabled(unread == 0)
        Divider()
        Button("Delete All Messages…", role: .destructive) { deleting = item }
      }
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
