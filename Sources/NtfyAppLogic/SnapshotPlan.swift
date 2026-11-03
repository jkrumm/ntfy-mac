import Foundation

/// Which look a UI snapshot is drawn in.
public enum SnapshotAppearance: String, Sendable, CaseIterable {
  case light, dark
}

/// The states of the menu bar popover that are reviewed.
public enum PopoverScenario: String, Sendable, CaseIterable {
  case empty, messages, pausedUntil, pausedIndefinitely, meeting, presenting, disconnected, hover
}

/// The states of the History window that are reviewed.
public enum HistoryScenario: String, Sendable, CaseIterable {
  /// The urgent message with an attachment and actions is selected.
  case selected
  /// Nothing is selected.
  case all
  /// Priority, date and unread filters are on.
  case filtered
  /// A message with a very long title and body is selected.
  case long
  /// The filters hide every message.
  case noMatch
  case empty
  /// The New message popover: idle, sending and failed.
  case newMessage, sending, failed
}

/// One image of the UI snapshot set: what is drawn and at which size. The app's snapshot build
/// draws every entry of `SnapshotPlan.specs` in both appearances; the plan is plain values so a
/// test can check that no window or settings section is missing from it.
public struct SnapshotSpec: Sendable, Hashable, Identifiable {
  public enum Target: Sendable, Hashable {
    case popover(PopoverScenario)
    case history(HistoryScenario)
    case settings(SettingsSection)
    case onboarding(OnboardingModel.Step)

    /// The window this shows; nil for the popover.
    public var window: AppWindow? {
      switch self {
      case .popover: nil
      case .history: .history
      case .settings: .settings
      case .onboarding: .onboarding
      }
    }

    /// The first part of the file name.
    public var surface: String {
      switch self {
      case .popover: "popover"
      case .history: "history"
      case .settings: "settings"
      case .onboarding: "onboarding"
      }
    }

    /// The second part of the file name.
    public var state: String {
      switch self {
      case .popover(let scenario): scenario.rawValue
      case .history(let scenario): scenario.rawValue
      case .settings(let section): section.rawValue
      case .onboarding(let step): String(describing: step)
      }
    }
  }

  public let target: Target
  /// The content size. The popover's height is nil: it is as tall as its content.
  public let width: Int
  public let height: Int?

  public var id: String {
    "\(target.surface)-\(target.state)-\(width)x\(height.map(String.init) ?? "fit")"
  }

  public init(_ target: Target, width: Int, height: Int?) {
    self.target = target
    self.width = width
    self.height = height
  }

  public init(_ target: Target, size: WindowSize) {
    self.init(target, width: size.width, height: size.height)
  }

  /// `<surface>-<state>-<light|dark>-<WxH>.png`, with the height the image really has.
  public func fileName(_ appearance: SnapshotAppearance, renderedHeight: Int) -> String {
    "\(target.surface)-\(target.state)-\(appearance.rawValue)-\(width)x\(renderedHeight).png"
  }
}

/// Every image of the UI snapshot set. Adding a surface or a state is one line here.
public enum SnapshotPlan {
  public static let popoverWidth = 340

  public static let specs: [SnapshotSpec] = popovers + histories + settings + onboarding

  private static let popovers = PopoverScenario.allCases.map {
    SnapshotSpec(.popover($0), width: popoverWidth, height: nil)
  }

  /// The log with a selection and without, and the filtered one, at both sizes; the other states
  /// at the default size.
  private static let histories: [SnapshotSpec] = {
    let window = AppWindow.history
    let both: [HistoryScenario] = [.selected, .all, .filtered]
    let defaultOnly: [HistoryScenario] = [.long, .noMatch, .empty, .newMessage, .sending, .failed]
    return both.flatMap { scenario in
      [window.defaultSize, window.minimumSize].map { SnapshotSpec(.history(scenario), size: $0) }
    } + defaultOnly.map { SnapshotSpec(.history($0), size: window.defaultSize) }
  }()

  /// Every section at the default and the minimum size.
  private static let settings = SettingsSection.allCases.flatMap { section in
    [AppWindow.settings.defaultSize, AppWindow.settings.minimumSize].map {
      SnapshotSpec(.settings(section), size: $0)
    }
  }

  private static let onboarding = OnboardingModel.Step.allCases.map {
    SnapshotSpec(.onboarding($0), size: AppWindow.onboarding.defaultSize)
  }
}
