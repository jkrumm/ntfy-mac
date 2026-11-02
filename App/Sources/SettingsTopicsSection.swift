import NtfyAppLogic
import NtfyCore
import SwiftUI

struct SettingsTopicsSection: View {
  @Bindable var model: SettingsModel

  var body: some View {
    Form {
      Section {
        if model.topicRows.isEmpty {
          Text("No topics yet. Add one below, or connect a server with subscriptions.")
            .foregroundStyle(.secondary)
        }
        ForEach(model.topicRows) { row in
          TopicRowView(model: model, row: row)
        }
      } header: {
        Text("Topics")
      } footer: {
        Text(
          "Topics from your ntfy account are managed in the ntfy web app. Muted topics are still stored in the history."
        )
      }
      Section(settingLabel(.topicSubscribe)) {
        HStack {
          TextField("Topic name", text: $model.newTopicText)
            .autocorrectionDisabled()
            .onSubmit { Task { await model.addTypedTopic() } }
          Button("Add") { Task { await model.addTypedTopic() } }
            .disabled(model.newTopicText.isEmpty)
        }
        .help(settingCommandHint(.topicSubscribe))
      }
    }
    .formStyle(.grouped)
    .task { await model.reloadServerTopics() }
  }
}

private struct TopicRowView: View {
  let model: SettingsModel
  let row: TopicRow
  @State private var emoji: String
  @FocusState private var emojiFocused: Bool

  init(model: SettingsModel, row: TopicRow) {
    self.model = model
    self.row = row
    _emoji = State(initialValue: row.settings.emoji ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(row.name).fontWeight(.semibold)
        Text(origin).font(.caption).foregroundStyle(.secondary)
        Spacer()
        if row.isLocal {
          Button("Remove", role: .destructive) { Task { await model.unsubscribe(row.name) } }
            .help(settingCommandHint(.topicUnsubscribe))
        }
      }
      HStack(spacing: 16) {
        Toggle(
          "Mute",
          isOn: Binding(
            get: { row.settings.mute },
            set: { value in Task { await model.setMute(value, topic: row.name) } })
        )
        .help(settingCommandHint(.topicMute))
        Picker("Minimum priority", selection: priority) {
          Text("Any").tag(0)
          ForEach(SettingsModel.priorities, id: \.self) { value in
            Text(SettingsModel.priorityTitle(value)).tag(value)
          }
        }
        .help(settingCommandHint(.topicMinPriority))
        TextField("Emoji", text: $emoji)
          .frame(width: 80)
          .focused($emojiFocused)
          .onSubmit(commitEmoji)
          .onChange(of: emojiFocused) { if !emojiFocused { commitEmoji() } }
          .help(settingCommandHint(.topicEmoji))
      }
    }
    .padding(.vertical, 2)
  }

  private var priority: Binding<Int> {
    Binding(
      get: { row.settings.minPriority ?? 0 },
      set: { value in
        Task { await model.setMinPriority(value == 0 ? nil : value, topic: row.name) }
      })
  }

  private var origin: String {
    switch row.origin {
    case .server: "on the server"
    case .local: "added here"
    case .seen: "seen in the history"
    }
  }

  private func commitEmoji() {
    guard emoji != (row.settings.emoji ?? "") else { return }
    Task { await model.setEmoji(emoji, topic: row.name) }
  }
}
