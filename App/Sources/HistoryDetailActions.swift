import AppKit
import NtfyAppLogic
import SwiftUI

/// Acknowledge, read state, remind, copy and delete for the shown message.
struct HistoryDetailActions: View {
  let model: HistoryModel
  let detail: MessageDetail
  @Binding var confirmingDelete: Bool

  var body: some View {
    HStack {
      Button {
        Task { await model.acknowledge() }
      } label: {
        Label("Acknowledge", systemImage: "checkmark.circle")
      }
      .disabled(detail.isAcknowledged)

      Button {
        Task { if detail.isRead { await model.markUnread() } else { await model.markRead() } }
      } label: {
        Label(
          detail.isRead ? "Mark Unread" : "Mark Read",
          systemImage: detail.isRead ? "envelope.badge" : "envelope.open")
      }

      Menu {
        ForEach(RemindChoice.allCases, id: \.self) { choice in
          Button(choice.title) { Task { await model.remind(choice) } }
        }
      } label: {
        Label("Remind", systemImage: "bell")
      }
      .fixedSize()

      Button {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(detail.body, forType: .string)
      } label: {
        Label("Copy Body", systemImage: "doc.on.doc")
      }
      .disabled(detail.body.isEmpty)

      Spacer()

      Button(role: .destructive) {
        confirmingDelete = true
      } label: {
        Label("Delete", systemImage: "trash")
      }
    }
    .controlSize(.regular)
  }
}
