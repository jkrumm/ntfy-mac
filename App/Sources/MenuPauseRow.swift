import NtfyAppLogic
import SwiftUI

/// The pause control of the popover. Idle: a row that expands inline to the durations, one click per
/// choice. Paused: the end of the pause and a prominent Resume button.
struct MenuPauseRow: View {
  let model: AppModel
  @State private var expanded = false

  var body: some View {
    if let until = model.pausedUntil {
      paused(until: until)
    } else {
      VStack(alignment: .leading, spacing: 2) {
        MenuRow("Pause notifications", systemImage: "bell.slash") {
          expanded.toggle()
        } trailing: {
          Image(systemName: expanded ? "chevron.down" : "chevron.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        if expanded { choices }
      }
    }
  }

  private var choices: some View {
    VStack(alignment: .leading, spacing: 2) {
      choice("30 minutes", .duration(30 * 60))
      choice("1 hour", .duration(60 * 60))
      choice("2 hours", .duration(2 * 60 * 60))
      choice("Until 08:00", .untilMorning)
      choice("Until I resume", .indefinitely)
    }
    .padding(.leading, 24)
  }

  private func choice(_ title: String, _ value: PauseChoice) -> some View {
    Button {
      Task { await model.pause(value) }
    } label: {
      Text(title)
    }
    .buttonStyle(.menuRow)
  }

  private func paused(until: Date) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "bell.slash.fill")
        .frame(width: 16)
        .foregroundStyle(.orange)
      Text(model.isPausedIndefinitely ? "Paused until I resume" : "Paused until \(time(until))")
      Spacer(minLength: 8)
      Button("Resume") { Task { await model.resume() } }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }
    .padding(.horizontal, 6)
    .padding(.vertical, 2)
  }

  private func time(_ date: Date) -> String {
    date.formatted(.dateTime.hour().minute())
  }
}
