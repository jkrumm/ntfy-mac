import NtfyAppLogic
import SwiftUI

/// A small sheet for one topic's emoji: the same trim and clear rules as the Settings window
/// (`HistoryModel.setEmoji`, a blank field removes it).
struct TopicEmojiSheet: View {
  let model: HistoryModel
  let topic: String
  @Environment(\.dismiss) private var dismiss
  @State private var emoji: String

  init(model: HistoryModel, topic: String) {
    self.model = model
    self.topic = topic
    _emoji = State(initialValue: model.emoji(for: topic) ?? "")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Emoji for \(topic)")
        .font(.headline)
      TextField("Emoji", text: $emoji)
        .labelsHidden()
        .frame(width: 120)
        .onSubmit(save)
      Text("Shown before the topic name here, and in front of its notification titles.")
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      HStack {
        Button("Remove") {
          emoji = ""
          save()
        }
        .disabled(model.emoji(for: topic) == nil)
        Spacer()
        Button("Cancel", role: .cancel) { dismiss() }
          .keyboardShortcut(.cancelAction)
        Button("Save", action: save)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(16)
    .frame(width: 280)
  }

  private func save() {
    Task {
      await model.setEmoji(emoji, topic: topic)
      dismiss()
    }
  }
}
