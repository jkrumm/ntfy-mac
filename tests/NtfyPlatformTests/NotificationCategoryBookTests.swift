import Testing

@testable import NtfyPlatform

@Suite struct NotificationCategoryBookTests {
  private func category(_ id: String, _ buttons: [String] = []) -> NotificationCategorySpec {
    NotificationCategorySpec(
      identifier: "ntfy:\(id)", actions: buttons.map { NotificationActionSpec(id: $0, title: $0) })
  }

  private func merged(
    existing: [NotificationCategorySpec] = [], adding: [NotificationCategorySpec] = [],
    delivered: Set<String> = [], limit: Int = 64
  ) -> [String] {
    NotificationCategoryBook.merged(
      existing: existing, adding: adding, delivered: delivered, limit: limit
    ).map(\.identifier)
  }

  @Test func addedCategoriesSurviveWithoutBeingDelivered() {
    #expect(merged(adding: [category("a")]) == ["ntfy:a"])
  }

  @Test func aCategoryWithTheSameIdentifierIsReplacedNotDuplicated() {
    let result = NotificationCategoryBook.merged(
      existing: [category("a", ["old"])], adding: [category("a", ["new"])], delivered: ["a"],
      limit: 64)
    #expect(result == [category("a", ["new"])])
  }

  @Test func categoriesOfNotificationsNoLongerShownAreDropped() {
    #expect(merged(existing: [category("a"), category("b")], delivered: ["b"]) == ["ntfy:b"])
  }

  @Test func foreignCategoriesAreDropped() {
    let foreign = NotificationCategorySpec(identifier: "other", actions: [])
    #expect(merged(existing: [foreign, category("a")], delivered: ["a", "other"]) == ["ntfy:a"])
  }

  @Test func theCapKeepsTheAddedOnesFirstAndTheRestInStableOrder() {
    let existing = ["d", "b", "e", "a", "c"].map { category($0) }
    let result = merged(
      existing: existing, adding: [category("new")], delivered: ["a", "b", "c", "d", "e"],
      limit: 3)
    #expect(result == ["ntfy:new", "ntfy:a", "ntfy:b"])
  }

  @Test func theCapNeverExceedsTheLimitEvenForManyAdded() {
    let adding = (0..<10).map { category("n\($0)") }
    #expect(merged(adding: adding, limit: 4).count == 4)
  }

  @Test func theOutputOrderDoesNotDependOnTheInputOrder() {
    let forward = ["a", "b", "c"].map { category($0) }
    let delivered: Set<String> = ["a", "b", "c"]
    #expect(
      merged(existing: forward, delivered: delivered)
        == merged(existing: forward.reversed(), delivered: delivered))
  }
}
