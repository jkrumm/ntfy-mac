/// What the History window lets the user do to a message, and the command that does the same.
/// One table: the schema, the generated `docs/cli.md` and the parity test read it.
public enum UIActionID: String, Sendable, CaseIterable, Hashable {
  case acknowledge
  case markRead
  case remind
  case delete
  case openClickURL
  case export
  case search
}

public struct UIActionEntry: Sendable, Hashable {
  public let id: UIActionID
  /// What the window calls it.
  public let label: String
  /// The command path without the program name.
  public let command: String
  public let example: String
  public let note: String?
}

public enum UIActionCatalog {
  public static let entries: [UIActionEntry] = [
    UIActionEntry(
      id: .acknowledge, label: "Acknowledge", command: "ack", example: "ntfy-mac ack alerts m1",
      note: "`--all --topic <topic>` acknowledges a whole topic."),
    UIActionEntry(
      id: .markRead, label: "Mark read", command: "read",
      example: "ntfy-mac read alerts m1 --json",
      note: "Reading a message marks it read; `--no-mark` leaves it. "
        + "Mark unread and mark all read have no command; "
        + "`ack --all --topic <topic>` also marks a topic read, and acknowledges it."
    ),
    UIActionEntry(
      id: .remind, label: "Remind me", command: "remind",
      example: "ntfy-mac remind alerts m1 --in 1h",
      note: "The window offers 15 minutes, 1 hour and tomorrow 08:00; `--until` takes any time."),
    UIActionEntry(
      id: .delete, label: "Delete", command: "delete", example: "ntfy-mac delete alerts m1",
      note: "`--topic <topic> --all` deletes every message of a topic."),
    UIActionEntry(
      id: .openClickURL, label: "Open click URL", command: "read",
      example: "ntfy-mac read alerts m1 --no-mark --json",
      note:
        "Read only: the URL is the `click` field. The window opens http, https and mailto links only."
    ),
    UIActionEntry(
      id: .export, label: "Export (JSON or CSV)", command: "ls",
      example: "ntfy-mac ls --json --topic alerts --limit 1000",
      note: "The window's JSON export has the same fields as `ls --json`."),
    UIActionEntry(
      id: .search, label: "Search and filter", command: "search",
      example: "ntfy-mac search deploy --topic builds --min-priority 4 --since 7d",
      note: "Topic, minimum priority, date and unread filters; `ls` takes the same without text."),
  ]
}
