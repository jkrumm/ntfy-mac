import NtfyAppLogic
import SwiftUI

/// Acknowledge (where it applies), read state, remind, copy and delete for the shown message.
/// Whole labels while they fit, else icons with the label as help: a label never truncates.
///
/// Acknowledging changes the message, and the bar must not move for it: the Acknowledge button
/// and the "Acknowledged" state share one slot (`InPlaceSwap`) sized for the wider of the two, and
/// so do "Mark Read" and "Mark Unread" (acknowledging reads the message). Before this, the button
/// left the bar, the "Acknowledged" label joined the wrapping header above it and the read toggle
/// changed its width, so every control right of the button and the content below shifted.
struct HistoryDetailActions: View {
  let model: HistoryModel
  let detail: MessageDetail
  @Binding var deleting: MessageKey?
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

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

  /// The Acknowledge button while the message waits for one, "Acknowledged" once it has one, and
  /// nothing for a message that never needs one.
  @ViewBuilder private var acknowledge: some View {
    let pending = model.canAcknowledge(detail)
    if pending || detail.isAcknowledged {
      InPlaceSwap(showsFirst: pending, animated: !reduceMotion) {
        Button {
          Task { await model.acknowledge() }
        } label: {
          Label("Acknowledge", systemImage: "checkmark.circle")
        }
        .buttonStyle(.borderedProminent)
        .help("Acknowledge")
      } second: {
        Label("Acknowledged", systemImage: "checkmark.circle.fill")
          .font(.subheadline)
          .foregroundStyle(.green)
          .help("Acknowledged")
      }
    }
  }

  private var others: some View {
    HStack(spacing: 6) {
      Button {
        Task { if detail.isRead { await model.markUnread() } else { await model.markRead() } }
      } label: {
        InPlaceSwap(showsFirst: detail.isRead, animated: false) {
          Label("Mark Unread", systemImage: "envelope.badge")
        } second: {
          Label("Mark Read", systemImage: "envelope.open")
        }
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

/// Two states of one control in one slot: both are laid out, so the slot has the size of the wider
/// and taller of them whichever shows, and the other is invisible and out of reach. The change is
/// a short cross-fade, or none when `animated` is false (Reduce Motion).
struct InPlaceSwap<First: View, Second: View>: View {
  let showsFirst: Bool
  let animated: Bool
  @ViewBuilder let first: First
  @ViewBuilder let second: Second

  var body: some View {
    ZStack {
      first
        .disabled(!showsFirst)
        .opacity(showsFirst ? 1 : 0)
        .allowsHitTesting(showsFirst)
        .accessibilityHidden(!showsFirst)
      second
        .opacity(showsFirst ? 0 : 1)
        .allowsHitTesting(!showsFirst)
        .accessibilityHidden(showsFirst)
    }
    .animation(animated ? .easeInOut(duration: 0.15) : nil, value: showsFirst)
  }
}
