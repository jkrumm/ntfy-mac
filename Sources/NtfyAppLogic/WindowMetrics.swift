import Foundation

/// A window size in points.
public struct WindowSize: Sendable, Hashable {
  public let width: Int
  public let height: Int

  public init(_ width: Int, _ height: Int) {
    self.width = width
    self.height = height
  }

  public var description: String { "\(width)x\(height)" }
}

extension AppWindow {
  /// The size the window opens at. One value for the scene's `defaultSize` and for the UI
  /// snapshots, so what is reviewed is what ships.
  public var defaultSize: WindowSize {
    switch self {
    case .history: WindowSize(1000, 680)
    case .settings: WindowSize(780, 580)
    case .onboarding: WindowSize(520, 420)
    }
  }

  /// The smallest size the content is laid out for; the window cannot shrink below it.
  public var minimumSize: WindowSize {
    switch self {
    case .history: WindowSize(760, 480)
    case .settings: WindowSize(680, 480)
    case .onboarding: WindowSize(520, 420)
    }
  }
}
