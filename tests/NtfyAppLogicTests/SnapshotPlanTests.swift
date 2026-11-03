import Testing

@testable import NtfyAppLogic

/// The UI snapshot set is a review aid, but it must not silently miss a window or a settings
/// section: these tests fail when one is added without an entry in `SnapshotPlan`.
@Suite struct SnapshotPlanTests {
  private let specs = SnapshotPlan.specs

  @Test func everySettingsSectionIsDrawnAtBothSizes() {
    for section in SettingsSection.allCases {
      let sizes = specs.compactMap { spec -> WindowSize? in
        guard case .settings(section) = spec.target else { return nil }
        return WindowSize(spec.width, spec.height ?? 0)
      }
      #expect(sizes.contains(AppWindow.settings.defaultSize), "\(section) default size")
      #expect(sizes.contains(AppWindow.settings.minimumSize), "\(section) minimum size")
    }
  }

  @Test func everyWindowIsCovered() {
    let covered = Set(specs.compactMap(\.target.window))
    #expect(covered == Set(AppWindow.allCases))
    #expect(specs.contains { $0.target.window == nil }, "the popover")
  }

  @Test func theResizableWindowsAreDrawnAtDefaultAndMinimumSize() {
    for window in [AppWindow.history, .settings] {
      let sizes = Set(
        specs.filter { $0.target.window == window }.map { WindowSize($0.width, $0.height ?? 0) })
      #expect(sizes == [window.defaultSize, window.minimumSize], "\(window)")
    }
  }

  @Test func everyOnboardingStepAndPopoverStateIsDrawn() {
    for step in OnboardingModel.Step.allCases {
      #expect(specs.contains { $0.target == .onboarding(step) }, "\(step)")
    }
    for scenario in PopoverScenario.allCases {
      #expect(specs.contains { $0.target == .popover(scenario) }, "\(scenario)")
    }
    for scenario in HistoryScenario.allCases {
      #expect(specs.contains { $0.target == .history(scenario) }, "\(scenario)")
    }
  }

  @Test func fileNamesAreUniqueAndFollowTheScheme() {
    let names = specs.flatMap { spec in
      SnapshotAppearance.allCases.map { spec.fileName($0, renderedHeight: spec.height ?? 400) }
    }
    #expect(Set(names).count == names.count)
    #expect(Set(specs.map(\.id)).count == specs.count)
    for name in names {
      #expect(
        name.wholeMatch(of: /[A-Za-z]+-[A-Za-z]+-(light|dark)-\d+x\d+\.png/) != nil, "\(name)")
    }
  }

  @Test func windowSizesLeaveRoomAndTheMinimumIsSmaller() {
    for window in AppWindow.allCases {
      #expect(window.minimumSize.width <= window.defaultSize.width)
      #expect(window.minimumSize.height <= window.defaultSize.height)
    }
    #expect(
      AppWindow.history.defaultSize.width >= 980 && AppWindow.history.defaultSize.height >= 680)
    #expect(
      AppWindow.settings.defaultSize.width >= 760 && AppWindow.settings.defaultSize.height >= 560)
  }
}
