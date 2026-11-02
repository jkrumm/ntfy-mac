import Foundation
import NtfyCore

public struct SystemClock: Clock {
  public init() {}

  public func now() -> Date { Date() }

  public func sleep(for duration: Duration) async throws {
    try await ContinuousClock().sleep(for: duration)
  }
}
