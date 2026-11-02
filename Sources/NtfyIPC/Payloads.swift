import Foundation

/// A message in the history, by its key.
public struct MessageTarget: Codable, Sendable, Hashable {
  public let topic: String
  public let id: String

  public init(topic: String, id: String) {
    self.topic = topic
    self.id = id
  }
}

public struct RemindPayload: Codable, Sendable, Hashable {
  public let topic: String
  public let id: String
  public let until: Date

  public init(topic: String, id: String, until: Date) {
    self.topic = topic
    self.id = id
    self.until = until
  }
}

/// A local notification the CLI asks the app to post.
public struct NotifyPayload: Codable, Sendable, Hashable {
  public static let defaultPriority = 3

  public let title: String?
  public let body: String
  /// 1...5; the app clamps anything else.
  public let priority: Int
  public let tags: [String]
  public let clickURL: URL?
  public let dismissAfterSeconds: Double?

  public init(
    title: String? = nil, body: String, priority: Int = NotifyPayload.defaultPriority,
    tags: [String] = [], clickURL: URL? = nil, dismissAfterSeconds: Double? = nil
  ) {
    self.title = title
    self.body = body
    self.priority = priority
    self.tags = tags
    self.clickURL = clickURL
    self.dismissAfterSeconds = dismissAfterSeconds
  }

  /// Only `body` is required; the rest falls back to its default when absent.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    title = try container.decodeIfPresent(String.self, forKey: .title)
    body = try container.decode(String.self, forKey: .body)
    priority = try container.decodeIfPresent(Int.self, forKey: .priority) ?? Self.defaultPriority
    tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    clickURL = try container.decodeIfPresent(URL.self, forKey: .clickURL)
    dismissAfterSeconds = try container.decodeIfPresent(Double.self, forKey: .dismissAfterSeconds)
  }
}

/// One reason notifications are not as expected; mirrors `NtfyCore.PermissionProblem`.
public struct PermissionIssue: Codable, Sendable, Hashable {
  public let code: String
  public let hint: String

  public init(code: String, hint: String) {
    self.code = code
    self.hint = hint
  }
}

/// The notification permission as the app sees it; mirrors `NtfyCore.NotificationPermission`.
public struct PermissionSummary: Codable, Sendable, Hashable {
  /// Notifications can reach the user at all.
  public let usable: Bool
  public let problems: [PermissionIssue]

  public init(usable: Bool, problems: [PermissionIssue] = []) {
    self.usable = usable
    self.problems = problems
  }
}

public struct StatusResult: Codable, Sendable, Hashable {
  /// Stable lowercase name: `stopped`, `connecting`, `connected`, `backing-off`, `offline`,
  /// `paused`, `halted`.
  public let connection: String
  /// Notifications are held back until this time; nil when not paused.
  public let pausedUntil: Date?
  public let appVersion: String
  public let permission: PermissionSummary?

  public init(
    connection: String, pausedUntil: Date? = nil, appVersion: String,
    permission: PermissionSummary? = nil
  ) {
    self.connection = connection
    self.pausedUntil = pausedUntil
    self.appVersion = appVersion
    self.permission = permission
  }
}

public struct NotifyResult: Codable, Sendable, Hashable {
  /// The notification was handed to the delivery queue. False while notifications are paused;
  /// it is then stored and shown after the pause.
  public let posted: Bool

  public init(posted: Bool) { self.posted = posted }
}

/// The data a successful response carries; which field is set depends on the command.
public struct ResultPayload: Codable, Sendable, Hashable {
  public let status: StatusResult?
  public let notify: NotifyResult?
  public let permission: PermissionSummary?

  public init(
    status: StatusResult? = nil, notify: NotifyResult? = nil, permission: PermissionSummary? = nil
  ) {
    self.status = status
    self.notify = notify
    self.permission = permission
  }
}
