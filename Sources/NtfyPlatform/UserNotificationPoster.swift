import Foundation
import NtfyCore

/// `NotificationPoster` over the notification center.
///
/// - A post replaces a delivered notification with the same identifier: remove, register the
///   category, add.
/// - Actors are reentrant, so the whole remove-register-add sequence of a post (and every
///   category restore) runs behind a serial gate: one at a time, in arrival order. The gate is
///   not cancellation-aware; a waiter that is cancelled still waits its turn.
/// - The category set lives here, not in the center: the poster is its only writer, merges in
///   one synchronous step and pushes the result. Categories belong to the notifications still
///   shown plus the ones being posted right now (`inFlight`), capped at `maxCategories`. The
///   center's own delivered list can lag behind an add, which is why in-flight identifiers are
///   never pruned.
/// - Nothing here throws except as `NtfyError`, and nothing crashes on a failed attachment: an
///   image is optional.
public actor UserNotificationPoster: NotificationPoster {
  public static let maxCategories = 64

  private let center: any NotificationCenterClient
  private let images: any ImageFetching
  private let log: @Sendable (String) -> Void

  private var categories: [String: NotificationCategorySpec] = [:]
  private var inFlight: Set<String> = []
  private var gateBusy = false
  private var gateWaiters: [CheckedContinuation<Void, Never>] = []

  public init(
    center: any NotificationCenterClient, images: any ImageFetching,
    log: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.center = center
    self.images = images
    self.log = log
  }

  public func post(_ content: NotificationContent) async throws(NtfyError) {
    var file: URL?
    if let imageURL = content.imageURL { file = await images.fetch(imageURL) }
    if content.imageURL != nil, file == nil { log("image not attached to \(content.identifier)") }
    let spec = UserNotificationMapper.spec(for: content, attachment: file)

    await enterGate()
    defer { leaveGate() }
    inFlight.insert(spec.identifier)
    defer { inFlight.remove(spec.identifier) }
    await center.removeDelivered(identifiers: [content.identifier])
    await register(spec.category.map { [$0] } ?? [])
    do throws(NtfyError) {
      try await center.add(spec)
    } catch {
      // The system validates the attachment when it takes the request; an image it dislikes
      // must not cost the notification.
      guard spec.attachment != nil, error != .permissionDenied else { throw error }
      log("posting \(content.identifier) without its image: \(error)")
      try await center.add(spec.withoutAttachment())
    }
  }

  public func postMissedSummary(
    count: Int, oldestTopic: String, cause: MissedSummaryCause
  ) async throws(NtfyError) {
    let spec = UserNotificationMapper.summarySpec(
      count: count, oldestTopic: oldestTopic, cause: cause,
      identifier: UserNotificationMapper.summaryPrefix + UUID().uuidString)
    try await center.add(spec)
  }

  public func remove(identifiers: [String]) async {
    guard !identifiers.isEmpty else { return }
    await center.removeDelivered(identifiers: identifiers)
  }

  public func deliveredIdentifiers() async -> Set<String> {
    Set(await center.delivered().map(\.identifier))
  }

  /// The messages behind the notifications still shown, as their `userInfo` names them.
  public func deliveredRefs() async -> [MessageRef] {
    await center.delivered().compactMap { UserNotificationMapper.messageRef(from: $0.userInfo) }
  }

  /// Registers the categories of notifications shown before a restart, so their buttons work
  /// again. Contents without buttons are skipped.
  public func restoreCategories(for contents: [NotificationContent]) async {
    let specs = contents.filter { !$0.buttons.isEmpty }.map(UserNotificationMapper.category(for:))
    guard !specs.isEmpty else { return }
    await enterGate()
    defer { leaveGate() }
    let restored = Set(
      specs.compactMap { UserNotificationMapper.notificationIdentifier(ofCategory: $0.identifier) })
    inFlight.formUnion(restored)
    defer { inFlight.subtract(restored) }
    await register(specs)
  }

  /// Rebuilds the categories of every notification still shown from the history, as the
  /// response handler will see them. A notification the history no longer knows is skipped.
  public func restoreDeliveredCategories(inbox: any HistoryInbox, config: Config) async {
    var contents: [NotificationContent] = []
    for ref in await deliveredRefs() {
      let stored = try? await inbox.message(topic: ref.topic, id: ref.id)
      guard let message = stored?.message else { continue }
      contents.append(DeliveryPolicy.content(for: message, config: config))
    }
    await restoreCategories(for: contents)
  }

  /// Merges `adding` into the category set and pushes it to the center. Call only behind the
  /// gate. The only suspension is the read of the delivered list, taken before the merge; the
  /// merge and the update of `categories` happen in one step after it.
  private func register(_ adding: [NotificationCategorySpec]) async {
    let delivered = Set(await center.delivered().map(\.identifier)).union(inFlight)
    let merged = NotificationCategoryBook.merged(
      existing: Array(categories.values), adding: adding, delivered: delivered,
      limit: Self.maxCategories)
    let next = Dictionary(uniqueKeysWithValues: merged.map { ($0.identifier, $0) })
    guard next != categories else { return }
    categories = next
    await center.setCategories(merged)
  }

  // MARK: Gate

  /// Operations queued behind the one holding the gate; tests use it to fix their arrival order.
  var gateQueueLength: Int { gateWaiters.count }

  private func enterGate() async {
    guard gateBusy else {
      gateBusy = true
      return
    }
    await withCheckedContinuation { gateWaiters.append($0) }
  }

  /// Hands the gate to the next waiter, which keeps it busy.
  private func leaveGate() {
    guard !gateWaiters.isEmpty else {
      gateBusy = false
      return
    }
    gateWaiters.removeFirst().resume()
  }
}
