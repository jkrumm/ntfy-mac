import Foundation
import Testing

@testable import NtfyCore

@Suite struct PriorityTests {
  @Test(arguments: [1, 2, 3, 4, 5])
  func acceptsValuesInRange(value: Int) {
    #expect(Priority(rawValue: value)?.rawValue == value)
  }

  @Test(arguments: [-1, 0, 6, 100])
  func rejectsValuesOutOfRange(value: Int) {
    #expect(Priority(rawValue: value) == nil)
  }

  @Test func clampingPinsToBounds() {
    #expect(Priority(clamping: -5) == .min)
    #expect(Priority(clamping: 99) == .max)
    #expect(Priority(clamping: 3) == .default)
  }

  @Test func ordersByRawValue() {
    #expect(Priority.low < Priority.high)
    #expect(Priority.min < Priority.max)
  }

  @Test func decodingRejectsOutOfRange() {
    let decoder = JSONDecoder()
    #expect(throws: DecodingError.self) { try decoder.decode(Priority.self, from: Data("7".utf8)) }
    #expect(throws: Never.self) { try decoder.decode(Priority.self, from: Data("5".utf8)) }
  }
}
