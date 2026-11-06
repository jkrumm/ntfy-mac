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

public struct AckAllPayload: Codable, Sendable, Hashable {
  /// Only this topic; nil acknowledges every topic.
  public let topic: String?

  public init(topic: String? = nil) { self.topic = topic }
}

public struct AckAllResult: Codable, Sendable, Hashable {
  /// How many messages were acknowledged.
  public let acknowledged: Int

  public init(acknowledged: Int) { self.acknowledged = acknowledged }
}

public struct DeletePayload: Codable, Sendable, Hashable {
  public let topic: String
  /// The message to delete; nil deletes every message of the topic.
  public let id: String?

  public init(topic: String, id: String? = nil) {
    self.topic = topic
    self.id = id
  }
}

public struct DeleteResult: Codable, Sendable, Hashable {
  /// How many messages were deleted.
  public let deleted: Int

  public init(deleted: Int) { self.deleted = deleted }
}

public struct UpdatePayload: Codable, Sendable, Hashable {
  /// Only look for an update, without any window; false starts the interactive update flow.
  public let check: Bool

  public init(check: Bool) { self.check = check }
}

/// Mirrors `NtfyCore.UpdateStatus`; the raw strings are the stable names.
public struct UpdateStatusPayload: Codable, Sendable, Hashable {
  /// `homebrew` or `direct`.
  public let channel: String
  public let currentVersion: String
  public let latestVersion: String?
  public let updateAvailable: Bool
  /// Why updating is not possible: `homebrew`, `unsigned`, `disabled` or `team-mismatch`.
  public let reason: String?

  public init(
    channel: String, currentVersion: String, latestVersion: String? = nil,
    updateAvailable: Bool = false, reason: String? = nil
  ) {
    self.channel = channel
    self.currentVersion = currentVersion
    self.latestVersion = latestVersion
    self.updateAvailable = updateAvailable
    self.reason = reason
  }
}

public struct LoginItemPayload: Codable, Sendable, Hashable {
  public enum Action: String, Codable, Sendable {
    /// Only read the state.
    case status
    case enable
    case disable
  }

  public let action: Action

  public init(action: Action = .status) { self.action = action }
}

public struct LoginItemResult: Codable, Sendable, Hashable {
  /// `enabled`, `requiresApproval`, `notRegistered` or `notFound`.
  public let state: String

  public init(state: String) { self.state = state }
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

/// Whether a meeting holds notifications back, as the app sees it. Added after the first v1
/// release: an older app leaves it out.
public struct MeetingSummary: Codable, Sendable, Hashable {
  /// Notifications are held back because of a meeting, detected or announced.
  public let active: Bool
  /// Why: `app`, `huddle`, `browser` or `presenting`; nil when not active.
  public let reason: String?
  /// The app behind the reason, when there is one.
  public let detail: String?
  /// The manual "I am presenting" override is on.
  public let presenting: Bool

  public init(active: Bool, reason: String? = nil, detail: String? = nil, presenting: Bool = false)
  {
    self.active = active
    self.reason = reason
    self.detail = detail
    self.presenting = presenting
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
  /// Nil from an app that predates meeting awareness.
  public let meeting: MeetingSummary?

  public init(
    connection: String, pausedUntil: Date? = nil, appVersion: String,
    permission: PermissionSummary? = nil, meeting: MeetingSummary? = nil
  ) {
    self.connection = connection
    self.pausedUntil = pausedUntil
    self.appVersion = appVersion
    self.permission = permission
    self.meeting = meeting
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
  public let ackAll: AckAllResult?
  public let loginItem: LoginItemResult?
  public let delete: DeleteResult?
  public let update: UpdateStatusPayload?

  public init(
    status: StatusResult? = nil, notify: NotifyResult? = nil, permission: PermissionSummary? = nil,
    ackAll: AckAllResult? = nil, loginItem: LoginItemResult? = nil, delete: DeleteResult? = nil,
    update: UpdateStatusPayload? = nil
  ) {
    self.status = status
    self.notify = notify
    self.permission = permission
    self.ackAll = ackAll
    self.loginItem = loginItem
    self.delete = delete
    self.update = update
  }
}
