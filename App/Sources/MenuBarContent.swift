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
    VStack(alignment: .leading, spacing: 10) {
      StatusLine(model: model, open: coordinator.show)
      if let problem = model.permission?.problems.first {
        Label(problem.hint, systemImage: "exclamationmark.triangle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .lineLimit(3)
          .fixedSize(horizontal: false, vertical: true)
      }
      Divider()
      messages
      Divider()
      actions
    }
    .padding(12)
    .frame(width: 340)
    .task { coordinator.install(openWindow) }
    .onChange(of: windows.request) { coordinator.fulfil(windows) }
    .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
      Task { await model.refreshPermission() }
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
            row: row, acknowledge: { Task { await model.acknowledge(row) } },
            open: {
              Task { await model.markRead(row) }
              windows.showHistory(selecting: row.key)
            })
        }
      }
    }
  }

  private var actions: some View {
    VStack(alignment: .leading, spacing: 6) {
      if model.unacknowledgedCount > 0 {
        Button("Acknowledge all") { Task { await model.acknowledgeAll() } }
      }
      PauseControl(model: model)
      Button("Open History") { coordinator.show(.history) }
      Button("Settings…") { coordinator.show(.settings) }
      Button("Quit ntfy-mac") { NSApp.terminate(nil) }
    }
    .buttonStyle(.plain)
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
      } else if model.connection.isDisconnected {
        Button("Reconnect") { Task { await model.reconnect() } }
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
          Text(row.topic)
          Text("·")
          Text(row.time, style: .relative)
          Text("ago")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      }
      Spacer(minLength: 4)
      if !row.isAcknowledged {
        Button(action: acknowledge) { Image(systemName: "checkmark.circle") }
          .buttonStyle(.borderless)
          .help("Acknowledge")
      }
    }
    .padding(.vertical, 3)
    .contentShape(Rectangle())
    .onTapGesture(perform: open)
  }

  private var marker: Color {
    if row.isUrgent { return row.priority >= .max ? .red : .orange }
    return row.isRead ? .clear : .accentColor
  }
}

private struct PauseControl: View {
  let model: AppModel

  var body: some View {
    if let until = model.pausedUntil {
      HStack {
        Text(model.isPausedIndefinitely ? "Paused until I resume" : "Paused until \(time(until))")
        Spacer()
        Button("Resume") { Task { await model.resume() } }
      }
    } else {
      Menu("Pause notifications") {
        Button("30 minutes") { pause(.duration(30 * 60)) }
        Button("1 hour") { pause(.duration(60 * 60)) }
        Button("2 hours") { pause(.duration(2 * 60 * 60)) }
        Button("Until 08:00") { pause(.untilMorning) }
        Button("Until I resume") { pause(.indefinitely) }
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
    }
  }

  private func pause(_ choice: PauseChoice) { Task { await model.pause(choice) } }

  private func time(_ date: Date) -> String {
    date.formatted(.dateTime.hour().minute())
  }
}
