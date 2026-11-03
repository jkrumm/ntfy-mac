import AppKit
import NtfyAppLogic
import NtfyCore
import SwiftUI

/// The popover of the menu bar item (`.window` style, so it is live).
struct MenuBarContent: View {
  let model: AppModel
  let windows: WindowRouter
  let coordinator: WindowCoordinator
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      header
      Divider().padding(.horizontal, 6)
      messages
      Divider().padding(.horizontal, 6)
      actions
    }
    .padding(6)
    .frame(width: 340)
    .task { coordinator.install(openWindow) }
    .onChange(of: windows.request) { coordinator.fulfil(windows) }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      Task { await model.refreshPermission() }
    }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 8) {
      StatusLine(model: model, open: coordinator.show)
      if let problem = model.permission?.problems.first {
        Label(problem.hint, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 4)
  }

  /// Meeting awareness: stop a presenting override, show a detected meeting, or offer to start one.
  @ViewBuilder private var statusRows: some View {
    if model.isPresentingOverride {
      MenuRow("Presenting: notifications held. Stop", systemImage: "rectangle.on.rectangle.slash") {
        Task { await model.setPresenting(false) }
      }
    } else if model.meetingActive {
      Label("In a meeting: notifications held", systemImage: "video.fill")
        .font(.callout)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
    } else {
      MenuRow("I'm presenting (1 hour)", systemImage: "rectangle.on.rectangle") {
        Task { await model.setPresenting(true) }
      }
    }
    if let problem = model.presentingError {
      Label(problem, systemImage: "exclamationmark.triangle.fill")
        .font(.caption)
        .foregroundStyle(.orange)
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 6)
    }
  }

  @ViewBuilder private var messages: some View {
    if model.recent.isEmpty {
      Text("No messages yet")
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    } else {
      VStack(alignment: .leading, spacing: 2) {
        ForEach(model.recent) { row in
          MessageRowView(
            row: row, showsAcknowledge: model.canAcknowledge(row),
            acknowledge: { Task { await model.acknowledge(row) } },
            open: {
              Task { await model.markRead(row) }
              windows.showHistory(selecting: row.key)
            })
        }
      }
    }
  }

  private var actions: some View {
    VStack(alignment: .leading, spacing: 2) {
      statusRows
      if model.unacknowledgedCount > 0 {
        MenuRow("Acknowledge all", systemImage: "checkmark.circle") {
          Task { await model.acknowledgeAll() }
        } trailing: {
          Text("\(model.unacknowledgedCount)")
            .font(.callout)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
      }
      MenuPauseRow(model: model)
      MenuRow("Open History", systemImage: "clock") { coordinator.show(.history) }
      MenuRow("Settings…", systemImage: "gearshape") { coordinator.show(.settings) }
      MenuRow("Quit ntfy-mac", systemImage: "power") { NSApp.terminate(nil) }
    }
  }
}

private struct StatusLine: View {
  let model: AppModel
  let open: (AppWindow) -> Void

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "circle.fill")
        .font(.system(size: 8))
        .foregroundStyle(color)
      Text(model.connection.title)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 8)
      if model.connection.needsSettings {
        Button("Open Settings") { open(.settings) }
          .buttonStyle(.menuRowCompact)
          .fixedSize()
      } else if model.connection.isDisconnected {
        Button("Reconnect") { Task { await model.reconnect() } }
          .buttonStyle(.menuRowCompact)
          .fixedSize()
      }
    }
  }

  private var color: Color {
    switch model.connection {
    case .connected: .green
    case .connecting, .sleeping: .yellow
    case .notConfigured: .gray
    case .retrying, .offline: .orange
    case .needsAttention: .red
    }
  }
}

private struct MessageRowView: View {
  let row: MessageRow
  /// Only messages that need an acknowledgement have the button; opening any other marks it read.
  let showsAcknowledge: Bool
  let acknowledge: () -> Void
  let open: () -> Void

  var body: some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: row.isUrgent ? "exclamationmark.circle.fill" : "circle.fill")
        .font(.system(size: row.isUrgent ? 12 : 6))
        .foregroundStyle(marker)
        .frame(width: 14, height: 16)
      VStack(alignment: .leading, spacing: 1) {
        Text(row.title)
          .fontWeight(row.isRead ? .regular : .semibold)
          .lineLimit(1)
        HStack(spacing: 4) {
          // A long topic gives way; the age stays whole.
          Text(row.topic).lineLimit(1)
          Text("·")
          Text(row.time, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
            .lineLimit(1)
            .fixedSize()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer(minLength: 4)
      if showsAcknowledge {
        Button(action: acknowledge) { Image(systemName: "checkmark.circle") }
          .buttonStyle(.borderless)
          .help("Acknowledge")
      }
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 4)
    .menuHover(id: row.id)
    .onTapGesture(perform: open)
  }

  private var marker: Color {
    if row.isUrgent { return row.priority >= .max ? .red : .orange }
    return row.isRead ? .clear : .accentColor
  }
}
