import NtfyCore
import NtfyPlatform

/// Records what the poster asked of the center and keeps the delivered and category state a real
/// one would. Never touches UserNotifications, which aborts without a bundle.
actor FakeNotificationCenter: NotificationCenterClient {
  enum Call: Equatable {
    case remove([String])
    case setCategories
    case add(String)
  }

  private(set) var calls: [Call] = []
  private(set) var added: [UserNotificationSpec] = []
  private(set) var registered: [NotificationCategorySpec] = []
  private var holdNext = false
  private var held: CheckedContinuation<Void, Never>?
  private var shown: [DeliveredNotification] = []
  private var failure: NtfyError?
  /// Nil fails every add while `failure` is set.
  private var failuresLeft: Int?
  private var snapshot = NotificationSettingsSnapshot(authorization: .authorized)
  private(set) var authorizationRequests = 0

  func failAdds(with error: NtfyError?) {
    failure = error
    failuresLeft = nil
  }

  /// Fails only the next `count` adds.
  func failNextAdds(_ count: Int, with error: NtfyError) {
    failure = error
    failuresLeft = count
  }

  func setRegistered(_ categories: [NotificationCategorySpec]) { registered = categories }
  func setShown(_ notifications: [DeliveredNotification]) { shown = notifications }

  /// Makes the next `add` suspend until `releaseHeldAdd()`, to interleave other calls with it.
  func holdNextAdd() { holdNext = true }

  var isHoldingAdd: Bool { held != nil }

  func releaseHeldAdd() {
    held?.resume()
    held = nil
  }

  func add(_ spec: UserNotificationSpec) async throws(NtfyError) {
    calls.append(.add(spec.identifier))
    if holdNext {
      holdNext = false
      await withCheckedContinuation { held = $0 }
    }
    if let failure, failuresLeft != 0 {
      failuresLeft = failuresLeft.map { $0 - 1 }
      throw failure
    }
    added.append(spec)
    shown.removeAll { $0.identifier == spec.identifier }
    shown.append(DeliveredNotification(identifier: spec.identifier, userInfo: spec.userInfo))
  }

  func removeDelivered(identifiers: [String]) {
    calls.append(.remove(identifiers))
    shown.removeAll { identifiers.contains($0.identifier) }
  }

  func delivered() -> [DeliveredNotification] { shown }

  func setCategories(_ categories: [NotificationCategorySpec]) {
    calls.append(.setCategories)
    registered = categories
  }

  func settings() -> NotificationSettingsSnapshot { snapshot }

  func requestAuthorization() -> Bool {
    authorizationRequests += 1
    return true
  }
}
