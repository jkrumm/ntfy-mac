import Foundation
import NtfyCore

/// `NotificationPoster` over the notification center.
///
/// - A post replaces a delivered notification with the same identifier: remove, register the
///   category, add. Categories live per launch, so the set is merged (never overwritten) and
///   kept to the notifications still shown, capped at `maxCategories`.
/// - Nothing here throws except as `NtfyError`, and nothing crashes on a failed attachment: an
///   image is optional.
/// - The actor serialises posts; category updates are read-modify-write and rely on that.
public actor UserNotificationPoster: NotificationPoster {
  public static let maxCategories = 64

  private let center: any NotificationCenterClient
  private let images: any ImageFetching
  private let log: @Sendable (String) -> Void

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

  public func postMissedSummary(count: Int, oldestTopic: String) async throws(NtfyError) {
    let spec = UserNotificationMapper.summarySpec(
      count: count, oldestTopic: oldestTopic, identifier: "summary/\(UUID().uuidString)")
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

  private func register(_ adding: [NotificationCategorySpec]) async {
    let delivered = Set(await center.delivered().map(\.identifier))
    let existing = await center.categories()
    let merged = NotificationCategoryBook.merged(
      existing: existing, adding: adding, delivered: delivered, limit: Self.maxCategories)
    guard Set(merged) != Set(existing) else { return }
    await center.setCategories(merged)
  }
}
