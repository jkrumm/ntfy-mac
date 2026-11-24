/// Every setting the UI exposes, with the CLI command that sets it. One table: the schema, the
/// generated `docs/settings.md` and the parity test all read it, so a setting cannot reach the UI
/// without a command and a row.
public enum SettingID: String, Sendable, CaseIterable, Hashable {
  case serverURL
  case token
  case allowInsecure
  case topicSubscribe
  case topicUnsubscribe
  case topicMute
  case topicMinPriority
  case topicEmoji
  case topicHideFromAll
  case sounds
  case soundList
  case soundPreview
  case dismiss
  case quietHoursEnabled
  case quietHoursStart
  case quietHoursEnd
  case quietHoursUrgentBypass
  case quietHoursDigest
  case reAlert
  case reAlertIntervalSeconds
  case reAlertMinPriority
  case reAlertMaxRepeats
  case summaryEnabled
  case summaryEndpoint
  case summaryKey
  case summaryModel
  case summaryMinAwayMinutes
  case summaryMinMessages
  case meetingMode
  case meetingUrgentBypass
  case presenting
  case allowPrivateNetworkActions
  case loginItem
  case pause
  case notificationPermission
}

public enum SettingGroup: String, Sendable, CaseIterable, Hashable {
  case server
  case topics
  case sounds
  case quietHours
  case reAlert
  case meetings
  case summary
  case actions
  case system

  public var title: String {
    switch self {
    case .server: "Server"
    case .topics: "Topics"
    case .sounds: "Sounds and dismiss timing"
    case .quietHours: "Quiet hours"
    case .reAlert: "Re-alert"
    case .meetings: "Meetings"
    case .summary: "Away digest"
    case .actions: "Message actions"
    case .system: "System"
    }
  }
}

/// Where a setting's value lives.
public enum SettingStorage: String, Sendable, Hashable {
  /// `~/.config/ntfy-mac/config.json`.
  case config
  case keychain
  /// The login item or the notification permission, owned by macOS.
  case system

  public var title: String {
    switch self {
    case .config: "config.json"
    case .keychain: "Keychain"
    case .system: "System"
    }
  }
}

public enum SettingKind: String, Sendable, Hashable {
  /// Changed by a CLI command.
  case settable
  /// Shown by the UI, reported by a CLI command, changed by macOS.
  case readOnly
  /// Exists only in the UI; `note` says why.
  case uiOnly
}

public struct SettingEntry: Sendable, Hashable {
  public let id: SettingID
  public let group: SettingGroup
  public let label: String
  /// The path in `config.json` (`quietHours.start`; `<topic>` stands for a topic name), nil for
  /// the Keychain and system items.
  public let configKey: String?
  /// The command path without the program name (`config quiet-hours set`); nil only for `uiOnly`.
  public let command: String?
  /// One complete command line that parses; nil only for `uiOnly`.
  public let example: String?
  public let storage: SettingStorage
  public let kind: SettingKind
  /// Required for `uiOnly`; otherwise how to undo or complete the setting.
  public let note: String?

  init(
    _ id: SettingID, _ group: SettingGroup, _ label: String, key: String? = nil,
    command: String? = nil, example: String? = nil, storage: SettingStorage = .config,
    kind: SettingKind = .settable, note: String? = nil
  ) {
    self.id = id
    self.group = group
    self.label = label
    configKey = key
    self.command = command
    self.example = example
    self.storage = storage
    self.kind = kind
    self.note = note
  }

  /// The first segment of `configKey`: the top-level key in `config.json`.
  public var topLevelKey: String? { configKey?.split(separator: ".").first.map(String.init) }
}

public enum SettingsCatalog {
  public static func entry(_ id: SettingID) -> SettingEntry {
    guard let entry = entries.first(where: { $0.id == id }) else {
      preconditionFailure("SettingsCatalog has no entry for \(id)")
    }
    return entry
  }

  public static let entries: [SettingEntry] = [
    SettingEntry(
      .serverURL, .server, "Server URL", key: "url", command: "setup",
      example: "ntfy-mac setup --url https://ntfy.example.com --token tk_..."),
    SettingEntry(
      .token, .server, "Access token", command: "setup",
      example: "ntfy-mac setup --url https://ntfy.example.com --token tk_...",
      storage: .keychain),
    SettingEntry(
      .allowInsecure, .server, "Allow the token over plain http", key: "allowInsecure",
      command: "config set", example: "ntfy-mac config set allowInsecure true"),
    SettingEntry(
      .topicSubscribe, .topics, "Subscribe to a topic", key: "extraTopics",
      command: "subscribe", example: "ntfy-mac subscribe builds",
      note: "`subscribe reset` clears every local addition."),
    SettingEntry(
      .topicUnsubscribe, .topics, "Unsubscribe from a topic", key: "extraTopics",
      command: "unsubscribe", example: "ntfy-mac unsubscribe builds"),
    SettingEntry(
      .topicMute, .topics, "Mute a topic", key: "topicSettings.<topic>.mute",
      command: "config topic set", example: "ntfy-mac config topic set builds --mute",
      note: "`--unmute` undoes it; `config topic reset <topic>` clears all topic settings."),
    SettingEntry(
      .topicMinPriority, .topics, "Minimum priority of a topic",
      key: "topicSettings.<topic>.minPriority", command: "config topic set",
      example: "ntfy-mac config topic set builds --min-priority 4",
      note: "`--min-priority none` removes the filter."),
    SettingEntry(
      .topicEmoji, .topics, "Emoji of a topic", key: "topicSettings.<topic>.emoji",
      command: "config topic set", example: "ntfy-mac config topic set builds --emoji 🔨",
      note: "`--emoji none` removes it."),
    SettingEntry(
      .topicHideFromAll, .topics, "Hide a topic from All messages",
      key: "topicSettings.<topic>.hideFromAll", command: "config topic set",
      example: "ntfy-mac config topic set updates --hide-from-all",
      note: "Its messages still notify (unless muted) and show in the topic's own view and in "
        + "Unacknowledged; they leave All messages, its unread count and the menu bar. "
        + "`--show-in-all` undoes it."),
    SettingEntry(
      .sounds, .sounds, "Sound per priority", key: "sounds", command: "config sounds set",
      example: "ntfy-mac config sounds set 5 Sosumi",
      note: "`config sounds reset` restores the defaults; `silent` plays nothing."),
    SettingEntry(
      .soundList, .sounds, "Available sound names", command: "sounds",
      example: "ntfy-mac sounds", storage: .system, kind: .readOnly),
    SettingEntry(
      .soundPreview, .sounds, "Sound preview", command: "sounds", example: "ntfy-mac sounds",
      storage: .system, kind: .readOnly),
    SettingEntry(
      .dismiss, .sounds, "Auto-dismiss time per priority", key: "dismiss",
      command: "config dismiss set", example: "ntfy-mac config dismiss set 3 15",
      note: "`never` keeps the notification; `config dismiss reset` restores the defaults."),
    SettingEntry(
      .quietHoursEnabled, .quietHours, "Quiet hours on", key: "quietHours.enabled",
      command: "config quiet-hours set",
      example: "ntfy-mac config quiet-hours set --start 22:00 --end 07:00",
      note: "`set` turns it on; `config quiet-hours off` turns it off and keeps the times."),
    SettingEntry(
      .quietHoursStart, .quietHours, "Quiet hours start", key: "quietHours.start",
      command: "config quiet-hours set", example: "ntfy-mac config quiet-hours set --start 22:00"),
    SettingEntry(
      .quietHoursEnd, .quietHours, "Quiet hours end", key: "quietHours.end",
      command: "config quiet-hours set", example: "ntfy-mac config quiet-hours set --end 07:00"),
    SettingEntry(
      .quietHoursUrgentBypass, .quietHours, "Urgent messages bypass quiet hours",
      key: "quietHours.urgentBypass", command: "config quiet-hours set",
      example: "ntfy-mac config quiet-hours set --no-urgent-bypass"),
    SettingEntry(
      .quietHoursDigest, .quietHours, "Digest when quiet hours end", key: "quietHours.digest",
      command: "config quiet-hours set", example: "ntfy-mac config quiet-hours set --no-digest"),
    SettingEntry(
      .reAlert, .reAlert, "Re-alert until acknowledged", key: "reAlert",
      command: "config set", example: "ntfy-mac config set reAlert off"),
    SettingEntry(
      .reAlertIntervalSeconds, .reAlert, "Re-alert interval (seconds)",
      key: "reAlertIntervalSeconds", command: "config set",
      example: "ntfy-mac config set reAlertIntervalSeconds 600"),
    SettingEntry(
      .reAlertMinPriority, .reAlert, "Re-alert minimum priority", key: "reAlertMinPriority",
      command: "config set", example: "ntfy-mac config set reAlertMinPriority 4"),
    SettingEntry(
      .reAlertMaxRepeats, .reAlert, "Re-alert maximum repeats", key: "reAlertMaxRepeats",
      command: "config set", example: "ntfy-mac config set reAlertMaxRepeats 6"),
    SettingEntry(
      .meetingMode, .meetings, "Pause notifications during meetings", key: "meeting.mode",
      command: "config meeting set", example: "ntfy-mac config meeting set --mode pause",
      note: "`--mode off` turns it off; `config meeting reset` restores the defaults."),
    SettingEntry(
      .meetingUrgentBypass, .meetings, "Urgent messages bypass meetings",
      key: "meeting.urgentBypass", command: "config meeting set",
      example: "ntfy-mac config meeting set --no-urgent-bypass"),
    SettingEntry(
      .presenting, .meetings, "I am presenting", key: "meeting.presentingUntil",
      command: "present", example: "ntfy-mac present on --for 2h",
      note: "Holds notifications whatever the detection says, even with the mode off. "
        + "It lasts one hour unless you pass `--for` or `--indefinitely`; "
        + "`ntfy-mac present off` ends it."),
    SettingEntry(
      .summaryEnabled, .summary, "Summarize what I missed while away", key: "summary.enabled",
      command: "config set", example: "ntfy-mac config set summary.enabled on",
      note: "Off by default. It needs an endpoint and a key; without them nothing is sent."),
    SettingEntry(
      .summaryEndpoint, .summary, "Summary endpoint", key: "summary.endpoint",
      command: "config set",
      example: "ntfy-mac config set summary.endpoint https://api.anthropic.com",
      note: "The base URL of an Anthropic-compatible API; `/v1/messages` is appended. https "
        + "unless `allowInsecure` is on. An empty value clears it."),
    SettingEntry(
      .summaryKey, .summary, "Summary API key", command: "config summary-key set",
      example: "ntfy-mac config summary-key set", storage: .keychain,
      note: "Read from stdin, sent as `x-api-key`. `config summary-key clear` removes it."),
    SettingEntry(
      .summaryModel, .summary, "Summary model", key: "summary.model", command: "config set",
      example: "ntfy-mac config set summary.model claude-haiku-5-5",
      note: "A gateway may take an alias such as `haiku`. `config reset summary.model` "
        + "restores the default."),
    SettingEntry(
      .summaryMinAwayMinutes, .summary, "Minutes away before a digest",
      key: "summary.minAwayMinutes", command: "config set",
      example: "ntfy-mac config set summary.minAwayMinutes 15",
      note: "A digest covers what was shown since you last looked: the last digest, or the last "
        + "time you opened History or the menu bar. A pause, quiet hours or a meeting "
        + "hold it back; after a return from lock or sleep those messages roll into the next one."),
    SettingEntry(
      .summaryMinMessages, .summary, "Messages needed for a digest", key: "summary.minMessages",
      command: "config set", example: "ntfy-mac config set summary.minMessages 3"),
    SettingEntry(
      .allowPrivateNetworkActions, .actions, "Allow actions to reach the private network",
      key: "allowPrivateNetworkActions", command: "config set",
      example: "ntfy-mac config set allowPrivateNetworkActions true"),
    SettingEntry(
      .loginItem, .system, "Open at login", command: "login-item",
      example: "ntfy-mac login-item on", storage: .system),
    SettingEntry(
      .pause, .system, "Pause notifications", key: "pausedUntil", command: "pause",
      example: "ntfy-mac pause --for 30m", note: "`ntfy-mac resume` ends the pause."),
    SettingEntry(
      .notificationPermission, .system, "Notification permission", command: "status",
      example: "ntfy-mac status --json", storage: .system, kind: .readOnly,
      note: "macOS owns it; `doctor` explains what is missing."),
  ]
}
