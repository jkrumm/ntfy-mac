import AppKit
import NtfyAppLogic
import SwiftUI

/// The welcome window: three steps in one window. Closing it, by Finish or the close button,
/// dismisses the welcome for good (`WindowCoordinator` tells `OnboardingState`).
struct OnboardingWindow: View {
  @Bindable var model: OnboardingModel
  @Environment(\.dismiss) private var dismiss

  private static let activation = NotificationCenter.default.publisher(
    for: NSApplication.didBecomeActiveNotification)

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text(model.step.title).font(.title2.bold())
      Group {
        switch model.step {
        case .server: OnboardingServerStep(model: model)
        case .notifications: OnboardingNotificationsStep(model: model)
        case .login: OnboardingLoginStep(model: model)
        }
      }
      .frame(maxWidth: .infinity, alignment: .topLeading)
      Spacer(minLength: 0)
      footer
    }
    .padding(24)
    .frame(width: 520, height: 420)
    .onAppear { model.reset() }
    .onReceive(Self.activation) { _ in Task { await model.refreshPermission() } }
  }

  private var footer: some View {
    HStack {
      Text("Step \(model.step.rawValue + 1) of \(OnboardingModel.Step.allCases.count)")
        .font(.callout).foregroundStyle(.secondary)
      Spacer()
      if !model.isFirstStep {
        Button("Back") { model.back() }
      }
      if model.isLastStep {
        Button("Finish") {
          Task { if await model.finish() { dismiss() } }
        }
        .keyboardShortcut(.defaultAction)
      } else {
        if model.step == .server && !model.canContinue {
          Button("Skip for now") { model.next() }
        }
        Button("Continue") { model.next() }
          .keyboardShortcut(.defaultAction)
          .disabled(!model.canContinue)
      }
    }
  }
}
