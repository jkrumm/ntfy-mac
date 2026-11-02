import NtfyCore
import Testing

@testable import NtfyMacCLI

/// The settings catalog is the contract between the UI and the CLI: a setting the UI shows has a
/// command, a parsing example and a row in docs/settings.md.
@Suite struct SettingsParityTests {
  private static let readOnly: Set<SettingID> = [.soundList, .notificationPermission]
  private static let uiOnly: Set<SettingID> = [.soundPreview]

  private func commandPaths() throws -> Set<String> {
    let document = try SchemaBuilder.build(root: NtfyMac.self)
    func paths(_ command: CommandSchema) -> [String] {
      [command.path] + command.subcommands.flatMap(paths)
    }
    return Set(document.commands.flatMap(paths))
  }

  @Test func everySettingIDHasExactlyOneEntry() {
    let ids = SettingsCatalog.entries.map(\.id)
    #expect(Set(ids).count == ids.count, "duplicate id")
    #expect(Set(ids) == Set(SettingID.allCases))
    for id in SettingID.allCases {
      #expect(SettingsCatalog.entry(id).id == id)
    }
  }

  @Test func everyCommandPathResolvesInTheRealCommandTree() throws {
    let paths = try commandPaths()
    for entry in SettingsCatalog.entries {
      guard let command = entry.command else { continue }
      #expect(paths.contains("ntfy-mac " + command), "\(entry.id): no command \(command)")
    }
  }

  @Test func everyExampleParsesAndUsesItsCommand() throws {
    for entry in SettingsCatalog.entries {
      guard let command = entry.command, let example = entry.example else { continue }
      #expect(example.hasPrefix("ntfy-mac "), "\(entry.id)")
      let words = ExampleWords.split(example)
      let path = ["ntfy-mac"] + command.split(separator: " ").map(String.init)
      let verbs = path.count
      // `config topic set builds --mute`: the command path is the example's leading words.
      #expect(Array(words.prefix(verbs)) == path, "\(entry.id): \(example)")
      #expect(throws: Never.self, Comment(rawValue: example)) {
        _ = try NtfyMac.parseAsRoot(Array(words.dropFirst()))
      }
    }
  }

  @Test func everySettableExampleRunsSuccessfully() async {
    for entry in SettingsCatalog.entries where entry.kind != .uiOnly {
      guard let example = entry.example else { continue }
      let rig = CLIRig()
      await rig.config.update { $0.extraTopics = ["builds"] }
      let words = ExampleWords.split(example)
      let result = await rig.run(Array(words.dropFirst()))
      #expect(result.exit == .success, "\(entry.id): \(example) -> \(result.stderr)")
    }
  }

  @Test func uiOnlyEntriesHaveAReasonAndNothingElseDoes() {
    for entry in SettingsCatalog.entries {
      switch entry.kind {
      case .uiOnly:
        #expect(Self.uiOnly.contains(entry.id), "\(entry.id) must have a CLI command")
        #expect(entry.note?.isEmpty == false, "\(entry.id): uiOnly needs a reason")
        #expect(entry.command == nil && entry.example == nil)
      case .readOnly:
        #expect(Self.readOnly.contains(entry.id), "\(entry.id) must be settable")
        #expect(entry.command != nil && entry.example != nil)
      case .settable:
        #expect(entry.command != nil && entry.example != nil, "\(entry.id)")
      }
    }
    #expect(Set(SettingsCatalog.entries.filter { $0.kind == .uiOnly }.map(\.id)) == Self.uiOnly)
  }

  @Test func everyUserSettableConfigKeyIsInTheCatalog() {
    let covered = Set(SettingsCatalog.entries.compactMap(\.topLevelKey))
    // The token lives in the Keychain; the file key only exists for the 1.x migration.
    let settable = Config.knownKeys.subtracting(["token"])
    #expect(settable.subtracting(covered).isEmpty, "keys without a catalog row")
    #expect(covered.subtracting(settable).isEmpty, "catalog rows for unknown keys")
  }

  @Test func everyScalarConfigKeyHasACatalogRowAndRoundTripsThroughSet() async {
    let keys = Set(SettingsCatalog.entries.compactMap(\.configKey))
    let setCommand = SettingsCatalog.entries.filter { $0.command == "config set" }
    #expect(Set(setCommand.compactMap(\.configKey)) == Set(ConfigKey.allCases.map(\.rawValue)))
    for key in ConfigKey.allCases {
      #expect(keys.contains(key.rawValue))
      let rig = CLIRig()
      let result = await rig.run("config", "set", key.rawValue, key.defaultValue.description)
      #expect(result.exit == .success, "\(key)")
    }
  }

  @Test func theSchemaCarriesTheCatalog() async throws {
    let document = try await CLIRig().run("schema", "--json").json()
    let settings = try #require(document["settings"] as? [[String: Any]])
    #expect(
      settings.compactMap { $0["id"] as? String } == SettingsCatalog.entries.map(\.id.rawValue))
    let mute = try #require(settings.first { $0["id"] as? String == "topicMute" })
    #expect(mute["command"] as? String == "config topic set")
    #expect(mute["storage"] as? String == "config")
    #expect(mute["configKey"] as? String == "topicSettings.<topic>.mute")
    let token = try #require(settings.first { $0["id"] as? String == "token" })
    #expect(token["storage"] as? String == "keychain")
    #expect(token["configKey"] == nil)
  }
}
