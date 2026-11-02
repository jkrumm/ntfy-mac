/// Which topics to subscribe to: the account's own, plus extras, unless an override replaces both.
public struct TopicSelection: Sendable, Hashable {
  /// When set, exactly these topics and no discovery.
  public var override: [String]?
  /// Added to whatever the account subscribes to.
  public var extra: [String]

  public init(override: [String]? = nil, extra: [String] = []) {
    self.override = override
    self.extra = extra
  }
}

public struct ResolvedTopics: Sendable, Hashable {
  public let topics: [String]
  /// Names the server would reject.
  public let invalid: [String]
  /// Valid names beyond the 150-topic limit of one subscription.
  public let overflow: [String]
}

public enum TopicResolver {
  /// One subscription holds at most 150 distinct topics (docs.ntfy.sh/subscribe/api).
  public static let maxTopics = 150

  public static func resolve(selection: TopicSelection, discovered: [String]) -> ResolvedTopics {
    let wanted = selection.override ?? (discovered + selection.extra)
    var seen: Set<String> = []
    var topics: [String] = []
    var invalid: [String] = []
    var overflow: [String] = []
    for name in wanted where seen.insert(name).inserted {
      if !isValid(name) {
        invalid.append(name)
      } else if topics.count < maxTopics {
        topics.append(name)
      } else {
        overflow.append(name)
      }
    }
    return ResolvedTopics(topics: topics, invalid: invalid, overflow: overflow)
  }

  /// Letters, digits, `_` and `-`, 1 to 64 characters (docs.ntfy.sh/publish).
  public static func isValid(_ name: String) -> Bool {
    (1...64).contains(name.utf8.count)
      && name.utf8.allSatisfy { byte in
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
          || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
          || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
          || byte == UInt8(ascii: "-") || byte == UInt8(ascii: "_")
      }
  }
}
