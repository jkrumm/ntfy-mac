/// Keeps the set of registered categories bounded: only those of notifications still shown, and
/// never more than `limit`.
enum NotificationCategoryBook {
  /// - Parameters:
  ///   - existing: what the center has registered.
  ///   - adding: categories to register; they win over an existing one with the same identifier
  ///     and survive the delivered filter.
  ///   - delivered: identifiers of the notifications currently shown.
  static func merged(
    existing: [NotificationCategorySpec], adding: [NotificationCategorySpec],
    delivered: Set<String>, limit: Int
  ) -> [NotificationCategorySpec] {
    let added = Set(adding.map(\.identifier))
    let kept =
      existing
      .filter { category in
        guard !added.contains(category.identifier),
          let id = UserNotificationMapper.notificationIdentifier(ofCategory: category.identifier)
        else { return false }
        return delivered.contains(id)
      }
      .sorted { $0.identifier < $1.identifier }
    return Array((adding + kept).prefix(limit))
  }
}
