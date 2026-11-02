import Foundation

/// Whether the first-launch welcome was dismissed. UI-only state, so it lives in UserDefaults and
/// not in the config file the CLI shares.
struct OnboardingState {
  private static let key = "onboardingDismissed"
  private let defaults: UserDefaults

  init(defaults: UserDefaults) { self.defaults = defaults }

  var isDismissed: Bool { defaults.bool(forKey: Self.key) }

  func dismiss() { defaults.set(true, forKey: Self.key) }
}
