import NtfyAppLogic
import SwiftUI

/// Acknowledge (where it applies), read state, remind, copy and delete for the shown message.
/// Whole labels while they fit, else icons with the label as help: a label never truncates.
struct HistoryDetailActions: View {
  let model: HistoryModel
  let detail: MessageDetail
  @Binding var deleting: MessageKey?

  var body: some View {
    ViewThatFits(in: .horizontal) {
      bar(.titles).fixedSize()
      bar(.iconsExceptAcknowledge).fixedSize()
      bar(.icons).fixedSize()
    }
    .controlSize(.small)
  }

  private enum Fit {
    case titles
    /// Acknowledge keeps its word as long as it can: it is the action a message is waiting for.
    case iconsExceptAcknowledge
    case icons
  }

  private func bar(_ fit: Fit) -> some View {
    HStack(spacing: 6) {
      if fit == .icons {
        acknowledge.labelStyle(.iconOnly)
      } else {
        acknowledge
      }
      if fit == .titles {
        others
      } else {
        others.labelStyle(.iconOnly)
      }
    }
  }

  @ViewBuilder private var acknowledge: some View {
    if model.canAcknowledge(detail) {
      Button {
        Task { await model.acknowledge() }
      } label: {
        Label("Acknowledge", systemImage: "checkmark.circle")
      }
      .buttonStyle(.borderedProminent)
      .help("Acknowledge")
    }
  }

  private var others: some View {
    HStack(spacing: 6) {
      Button {
        Task { if detail.isRead { await model.markUnread() } else { await model.markRead() } }
      } label: {
        Label(
          detail.isRead ? "Mark Unread" : "Mark Read",
          systemImage: detail.isRead ? "envelope.badge" : "envelope.open")
      }
      .help(detail.isRead ? "Mark unread" : "Mark read")
      Menu {
        ForEach(RemindChoice.allCases, id: \.self) { choice in
          Button(choice.title) { Task { await model.remind(choice) } }
        }
      } label: {
        Label("Remind", systemImage: "bell")
      }
      .help("Show this message again later")
      Menu {
        Button("Copy Text") {
          HistoryClipboard.copy(detail.body.isEmpty ? detail.title : detail.body)
        }
        if detail.hasTitle { Button("Copy Title") { HistoryClipboard.copy(detail.title) } }
        if let url = detail.clickURL {
          Button("Copy Link") { HistoryClipboard.copy(url.absoluteString) }
        }
      } label: {
        Label("Copy", systemImage: "doc.on.doc")
      }
      .help("Copy")
      Button(role: .destructive) {
        deleting = detail.key
      } label: {
        Label("Delete", systemImage: "trash")
      }
      .help("Delete")
    }
  }
}
