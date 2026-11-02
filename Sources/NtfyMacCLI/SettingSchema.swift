import NtfyCore

/// One row of `SettingsCatalog` as `schema --json` prints it.
struct SettingSchema: Encodable, Sendable {
  let id: String
  let group: String
  let groupTitle: String
  let label: String
  /// The path in config.json; absent for the Keychain and system items.
  let configKey: String?
  /// The command path without the program name; absent for UI-only settings.
  let command: String?
  let example: String?
  /// `config`, `keychain` or `system`.
  let storage: String
  let storageTitle: String
  /// `settable`, `readOnly` or `uiOnly`.
  let kind: String
  let note: String?

  init(_ entry: SettingEntry) {
    id = entry.id.rawValue
    group = entry.group.rawValue
    groupTitle = entry.group.title
    label = entry.label
    configKey = entry.configKey
    command = entry.command
    example = entry.example
    storage = entry.storage.rawValue
    storageTitle = entry.storage.title
    kind = entry.kind.rawValue
    note = entry.note
  }
}

/// One row of `UIActionCatalog` as `schema --json` prints it.
struct UIActionSchema: Encodable, Sendable {
  let id: String
  let label: String
  /// The command path without the program name.
  let command: String
  let example: String
  let note: String?

  init(_ entry: UIActionEntry) {
    id = entry.id.rawValue
    label = entry.label
    command = entry.command
    example = entry.example
    note = entry.note
  }
}
