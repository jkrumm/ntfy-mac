import AppKit
import NtfyAppLogic
import NtfyCore
import SwiftUI

/// The notification permission: what macOS says, what is wrong, and the way to fix it. It checks
/// again whenever the app becomes active, because the user fixes it in System Settings.
struct PermissionStatusView: View {
  let flow: NotificationPermissionFlow

  private static let activation = NotificationCenter.default.publisher(
    for: NSApplication.didBecomeActiveNotification)

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(headline, systemImage: symbol)
        .foregroundStyle(tint)
      ForEach(
        flow.problems.filter { $0 != .scheduledSummary && $0 != .timeSensitiveOff }, id: \.code
      ) { problem in
        Text(problem.hint)
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let warning = flow.scheduledSummaryWarning {
        Label(warning, systemImage: "clock.badge.exclamationmark")
          .font(.callout)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let warning = flow.timeSensitiveWarning {
        Label(warning, systemImage: "bell.slash")
          .font(.callout)
          .foregroundStyle(.orange)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack {
        if flow.canRequest {
          Button("Allow notifications") { Task { await flow.requestAuthorization() } }
            .disabled(flow.isRequesting)
        }
        if flow.needsSystemSettings || flow.scheduledSummaryWarning != nil
          || flow.timeSensitiveWarning != nil
        {
          Button("Open Notification Settings") { Task { await flow.openSystemSettings() } }
        }
      }
    }
    .task { await flow.refresh() }
    .onReceive(Self.activation) { _ in Task { await flow.refresh() } }
  }

  private var headline: String {
    guard let permission = flow.permission else { return "Checking" }
    switch permission.authorization {
    case .notDetermined: return "Not asked yet"
    case .denied: return "Notifications are off for ntfy-mac"
    case .authorized, .provisional, .ephemeral:
      return permission.isUsable ? "Notifications are allowed" : "Notifications are not visible"
    }
  }

  private var symbol: String {
    guard let permission = flow.permission else { return "ellipsis.circle" }
    if permission.isUsable {
      return flow.problems.isEmpty ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
    }
    return permission.authorization == .notDetermined ? "questionmark.circle" : "xmark.octagon.fill"
  }

  private var tint: Color {
    guard let permission = flow.permission else { return .secondary }
    if !permission.isUsable {
      return permission.authorization == .notDetermined ? .secondary : .red
    }
    return flow.problems.isEmpty ? .green : .orange
  }
}
