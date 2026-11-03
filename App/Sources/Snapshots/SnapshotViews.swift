#if SNAPSHOT_HARNESS
  import AppKit
  import NtfyAppLogic
  import NtfyCore
  import SwiftUI

  /// Maps a plan entry to the real view over the snapshot world, and drives the world into the
  /// state the entry names.
  @MainActor
  enum SnapshotViews {
    /// The id of the popover row that is drawn as hovered.
    static let hoveredRow = "alerts/al-2"

    static func content(for target: SnapshotSpec.Target, world: SnapshotWorld) -> AnyView {
      switch target {
      case .popover(let scenario):
        AnyView(
          MenuBarContent(model: world.app, windows: world.windows, coordinator: world.coordinator)
            .environment(\.snapshotHoverID, scenario == .hover ? hoveredRow : nil)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)))
      case .history(let scenario):
        AnyView(
          HistoryWindow(model: world.history, windows: world.windows)
            .overlay(alignment: .topTrailing) { newMessage(for: scenario, world: world) })
      case .settings(let section):
        AnyView(SettingsWindow(model: world.settings, section: section))
      case .onboarding:
        AnyView(OnboardingWindow(model: world.onboarding))
      }
    }

    /// Runs once the view is on screen (the windows reset themselves when they appear).
    static func prepare(_ target: SnapshotSpec.Target, world: SnapshotWorld) async {
      switch target {
      case .popover, .settings:
        await world.app.refreshPermission()
      case .history(let scenario):
        await prepareHistory(scenario, world: world)
      case .onboarding(let step):
        world.onboarding.urlText = "ntfy.example.com"
        if step == .notifications || step == .login { world.onboarding.next() }
        if step == .login { world.onboarding.next() }
      }
    }

    /// A popover is a window of its own, which the offscreen drawing cannot see: the real form is
    /// laid over the window where the toolbar button would put it.
    @ViewBuilder
    private static func newMessage(for scenario: HistoryScenario, world: SnapshotWorld)
      -> some View
    {
      if [.newMessage, .sending, .failed].contains(scenario) {
        HistoryNewMessage(model: world.history) {}
          .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.separator))
          .shadow(radius: 12, y: 4)
          .padding(.top, 6)
          .padding(.trailing, 70)
      }
    }

    private static func prepareHistory(_ scenario: HistoryScenario, world: SnapshotWorld) async {
      let model = world.history
      switch scenario {
      case .selected:
        model.selectedTopic = "alerts"
        await model.select(MessageKey(topic: "alerts", id: "al-1"))
        await loadAttachment(of: MessageKey(topic: "alerts", id: "al-1"), model: model)
      case .all, .empty:
        break
      case .filtered:
        model.minPriority = .high
        model.dateFilter = .week
        model.unreadOnly = true
        await model.refresh()
      case .long:
        model.selectedTopic = "home"
        await model.select(MessageKey(topic: "home", id: "ho-4"))
      case .noMatch:
        model.minPriority = .max
        model.dateFilter = .today
        model.unreadOnly = true
        model.selectedTopic = "home"
        await model.refresh()
      case .newMessage:
        model.selectedTopic = "ci"
        model.openComposer()
        model.draft = "Deploy finished, please check the staging build"
      case .sending, .failed:
        model.selectedTopic = "ci"
        model.openComposer()
        model.composerPriority = .high
        model.draft = "Deploy finished, please check the staging build"
        // The sending state never ends (the publisher hangs), so the send is not awaited.
        Task { await model.send() }
        try? await Task.sleep(for: .milliseconds(300))
      }
    }

    private static func loadAttachment(of key: MessageKey, model: HistoryModel) async {
      model.loadAttachment(for: key)
      for _ in 0..<50 {
        if case .ready = model.attachmentState(for: key) { break }
        try? await Task.sleep(for: .milliseconds(50))
      }
    }
  }

  private struct SnapshotHoverKey: EnvironmentKey {
    static let defaultValue: String? = nil
  }

  extension EnvironmentValues {
    /// The popover row drawn as hovered, by `MenuHover.rowID`. Snapshot builds only.
    var snapshotHoverID: String? {
      get { self[SnapshotHoverKey.self] }
      set { self[SnapshotHoverKey.self] = newValue }
    }
  }
#endif
