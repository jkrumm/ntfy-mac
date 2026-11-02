import ArgumentParser
import Foundation
import NtfyCore

/// The machine-readable command tree: ArgumentParser's own metadata (names, defaults, help,
/// repeatability) merged with `CommandSpec` (types, ranges, dependencies, error codes).
struct SchemaArgument: Encodable, Sendable {
  let name: String
  /// `option`, `flag` or `positional`.
  let kind: String
  let short: String?
  let type: String
  let defaultValue: String?
  let required: Bool
  let repeatable: Bool
  let values: [String]?
  let range: [Int]?
  let unit: String?
  let help: String?

  private enum CodingKeys: String, CodingKey {
    case name, kind, short, type, required, repeatable, values, range, unit, help
    case defaultValue = "default"
  }
}

struct SchemaNeeds: Encodable, Sendable {
  let app: String
  let server: Bool
  let files: Bool
  let note: String?
}

struct CommandSchema: Encodable, Sendable {
  let name: String
  let path: String
  let usage: String
  let abstract: String
  let discussion: String?
  /// Complete command lines; empty for subcommands (their parent lists them).
  let examples: [String]
  let needs: SchemaNeeds
  let errorCodes: [String]
  let arguments: [SchemaArgument]
  let subcommands: [CommandSchema]
}

struct SchemaDocument: Encodable, Sendable {
  let schemaVersion = 3
  let name: String
  let version: String
  let abstract: String
  let discussion: String?
  let exitCodes: [ExitCodeEntry]
  let errorCodes: [ErrorCatalog.Entry]
  let commands: [CommandSchema]
  /// Every setting the UI exposes and the command that sets it (`SettingsCatalog`).
  let settings: [SettingSchema]
  /// What the History window does to a message and the command that does the same.
  let uiActions: [UIActionSchema]

  struct ExitCodeEntry: Encodable, Sendable {
    let code: Int32
    let name: String
    let meaning: String
  }
}

enum SchemaBuilder {
  /// The tree for `root`. Throws when ArgumentParser's dump cannot be read.
  static func build<Root: ParsableCommand>(
    root: Root.Type, specs: [CommandSpec] = CommandSpec.all
  ) throws -> SchemaDocument {
    let dump = try JSONDecoder().decode(Dump.self, from: Data(root._dumpHelp().utf8))
    let lookup = Dictionary(uniqueKeysWithValues: specs.map { ($0.name, $0) })
    let commands = (dump.command.subcommands ?? []).filter(isListed).map {
      convert($0, path: [dump.command.commandName], spec: lookup[$0.commandName])
    }
    return SchemaDocument(
      name: dump.command.commandName, version: Version.current,
      abstract: dump.command.abstract ?? "", discussion: dump.command.discussion,
      exitCodes: ProcessExit.allCases.map {
        .init(
          code: $0.rawValue, name: "\($0)", meaning: ErrorCatalog.exitMeanings[$0] ?? "")
      },
      errorCodes: ErrorCatalog.errors, commands: commands,
      settings: SettingsCatalog.entries.map(SettingSchema.init),
      uiActions: UIActionCatalog.entries.map(UIActionSchema.init))
  }

  /// The top-level command names of the tree, for the completeness check.
  static func commandNames<Root: ParsableCommand>(_ root: Root.Type) throws -> [String] {
    let dump = try JSONDecoder().decode(Dump.self, from: Data(root._dumpHelp().utf8))
    return (dump.command.subcommands ?? []).filter(isListed).map(\.commandName)
  }

  private static func isListed(_ command: Dump.Command) -> Bool {
    command.commandName != "help" && command.shouldDisplay
  }

  private static func convert(
    _ command: Dump.Command, path: [String], spec: CommandSpec?
  ) -> CommandSchema {
    let full = path + [command.commandName]
    let arguments = (command.arguments ?? []).filter(isListed).map { argument($0, spec: spec) }
    return CommandSchema(
      name: command.commandName, path: full.joined(separator: " "),
      usage: usage(path: full, arguments),
      abstract: command.abstract ?? "", discussion: command.discussion,
      examples: path.count == 1 ? spec?.examples ?? [] : [],
      needs: SchemaNeeds(
        app: (spec?.app ?? .none).rawValue, server: spec?.server ?? false,
        files: spec?.files ?? false, note: spec?.note),
      errorCodes: (spec?.errors ?? []).sorted(), arguments: arguments,
      subcommands: (command.subcommands ?? []).filter(isListed).map {
        convert($0, path: full, spec: spec)
      })
  }

  private static func isListed(_ argument: Dump.Argument) -> Bool {
    guard argument.shouldDisplay else { return false }
    return !["help", "version"].contains(argument.preferredName?.name)
  }

  private static func argument(_ dump: Dump.Argument, spec: CommandSpec?) -> SchemaArgument {
    let long = dump.names?.first { $0.kind != "short" }?.name
    let short = dump.names?.first { $0.kind == "short" }?.name
    let name = dump.kind == "positional" ? (dump.valueName ?? "value") : "--" + (long ?? "")
    let domain = spec?.domains[dump.kind == "positional" ? name : "--" + (long ?? "")]
    let values = dump.allValues
    let isFlag = dump.kind == "flag"
    return SchemaArgument(
      name: name, kind: dump.kind, short: short.map { "-" + $0 },
      type: isFlag ? "boolean" : values != nil ? "enum" : domain?.type ?? "string",
      defaultValue: isFlag ? "false" : dump.defaultValue, required: !dump.isOptional,
      repeatable: dump.isRepeating, values: values?.sorted(),
      range: domain?.range.map { [$0.lowerBound, $0.upperBound] }, unit: domain?.unit,
      help: dump.abstract)
  }

  private static func usage(path: [String], _ arguments: [SchemaArgument]) -> String {
    let parts = arguments.filter { $0.name != "--json" }.map { argument -> String in
      let value = argument.values?.joined(separator: "|") ?? argument.type
      var text: String
      switch argument.kind {
      case "positional": text = "<\(argument.values == nil ? argument.name : value)>"
      case "flag": text = argument.name
      default: text = "\(argument.name) <\(value)>"
      }
      if argument.repeatable { text += "..." }
      return argument.required ? text : "[\(text)]"
    }
    return (path + parts).joined(separator: " ")
  }
}

/// The subset of ArgumentParser's `--experimental-dump-help` JSON the schema needs. Decoded
/// here because the library's own model is not a public product.
private struct Dump: Decodable {
  struct Name: Decodable {
    let kind: String
    let name: String
  }

  struct Argument: Decodable {
    let kind: String
    let shouldDisplay: Bool
    let isOptional: Bool
    let isRepeating: Bool
    let names: [Name]?
    let preferredName: Name?
    let valueName: String?
    let defaultValue: String?
    let allValues: [String]?
    let abstract: String?
  }

  struct Command: Decodable {
    let commandName: String
    let shouldDisplay: Bool
    let abstract: String?
    let discussion: String?
    let subcommands: [Command]?
    let arguments: [Argument]?
  }

  let command: Command
}

extension SchemaDocument {
  /// The same tree as a compact listing: one usage line per command with its abstract.
  func compactText() -> String {
    var lines = ["\(name) \(version): \(abstract)", "Every command takes --json.", ""]
    func add(_ command: CommandSchema) {
      lines.append(command.usage)
      lines.append("    \(command.abstract)")
      command.subcommands.forEach(add)
    }
    commands.forEach(add)
    lines += ["", "Exit codes:"]
    lines += exitCodes.map { "  \($0.code)  \($0.name): \($0.meaning)" }
    return lines.joined(separator: "\n")
  }
}
