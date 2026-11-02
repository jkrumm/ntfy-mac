/// Maps ntfy tag names (gemoji aliases) to emoji.
public enum TagEmoji {
  private static let table: [String: String] = Dictionary(
    TagEmojiData.lines.split(separator: "\n").compactMap { line in
      guard let space = line.firstIndex(of: " ") else { return nil }
      return (String(line[..<space]), String(line[line.index(after: space)...]))
    },
    uniquingKeysWith: { _, last in last })

  public static func emoji(for tag: String) -> String? { table[tag] }

  /// Known tags become their emoji, unknown tags stay text; joined by a space.
  public static func render(_ tags: [String]) -> String {
    tags.map { table[$0] ?? $0 }.joined(separator: " ")
  }

  /// Number of known aliases.
  public static var count: Int { table.count }
}
