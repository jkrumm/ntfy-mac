#!/usr/bin/env swift  // Generates docs/cli.md, docs/settings.md and llms.txt from the CLI's own command tree.  // Run: ntfy-mac schema --json | swift scripts/generate-cli-docs.swift [--out <dir>]
//      swift scripts/generate-cli-docs.swift <schema.json> [--out <dir>]
// Without --out the files go to the repo root. `make docs` and `make docs-check` wrap this.
// The output is deterministic and carries no version, so a release does not dirty the docs.
import Foundation

typealias JSON = [String: Any]

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(Data("generate-cli-docs: \(message)\n".utf8))
  exit(1)
}

// MARK: Input

var schemaPath: String?
var outDirectory = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent().deletingLastPathComponent()
var arguments = Array(CommandLine.arguments.dropFirst())
while let argument = arguments.first {
  arguments.removeFirst()
  if argument == "--out" {
    guard let value = arguments.first else { fail("--out needs a directory") }
    arguments.removeFirst()
    outDirectory = URL(fileURLWithPath: value, isDirectory: true)
  } else if argument != "-" {
    schemaPath = argument
  }
}

let input: Data
if let schemaPath {
  guard let data = FileManager.default.contents(atPath: schemaPath) else {
    fail("cannot read \(schemaPath)")
  }
  input = data
} else {
  input = FileHandle.standardInput.readDataToEndOfFile()
}
guard let root = try? JSONSerialization.jsonObject(with: input) as? JSON,
  let commands = root["commands"] as? [JSON],
  let exitCodes = root["exitCodes"] as? [JSON],
  let errorCodes = root["errorCodes"] as? [JSON],
  let settings = root["settings"] as? [JSON],
  let uiActions = root["uiActions"] as? [JSON],
  let schemaVersion = root["schemaVersion"] as? Int
else { fail("input is not an ntfy-mac schema document") }
guard schemaVersion == 3 else { fail("schemaVersion \(schemaVersion) is not supported (3)") }

let repository = "https://github.com/jkrumm/ntfy-mac"
let cliPage = "\(repository)/blob/master/docs/cli.md"
let settingsPage = "\(repository)/blob/master/docs/settings.md"
let readmePage = "\(repository)/blob/master/README.md"

// MARK: Helpers

func text(_ object: JSON, _ key: String) -> String { object[key] as? String ?? "" }
func list(_ object: JSON, _ key: String) -> [String] { object[key] as? [String] ?? [] }
func objects(_ object: JSON, _ key: String) -> [JSON] { object[key] as? [JSON] ?? [] }

func cell(_ value: String) -> String {
  value.replacingOccurrences(of: "|", with: "\\|").replacingOccurrences(of: "\n", with: " ")
}

func anchor(_ path: String) -> String {
  path.lowercased().replacingOccurrences(of: " ", with: "-")
}

func table(_ header: [String], _ rows: [[String]]) -> [String] {
  var lines = ["| " + header.joined(separator: " | ") + " |"]
  lines.append("|" + String(repeating: "-|", count: header.count))
  lines += rows.map { "| " + $0.map(cell).joined(separator: " | ") + " |" }
  return lines
}

/// ArgumentParser discussions wrap prose and indent examples; keep paragraphs and code blocks.
func discussion(_ raw: String) -> [String] {
  var output: [String] = []
  var paragraph: [String] = []
  var code: [String] = []
  func flushParagraph() {
    guard !paragraph.isEmpty else { return }
    output += [paragraph.joined(separator: " "), ""]
    paragraph = []
  }
  func flushCode() {
    guard !code.isEmpty else { return }
    output += ["```sh"] + code + ["```", ""]
    code = []
  }
  for line in raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
    if line.hasPrefix("  ") {
      flushParagraph()
      code.append(String(line.dropFirst(2)))
    } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
      flushParagraph()
      flushCode()
    } else {
      flushCode()
      paragraph.append(line)
    }
  }
  flushParagraph()
  flushCode()
  return output
}

func describe(_ argument: JSON) -> String {
  var parts: [String] = []
  let help = text(argument, "help")
  if !help.isEmpty { parts.append(help) }
  if argument["repeatable"] as? Bool == true { parts.append("Repeatable.") }
  return parts.joined(separator: " ")
}

func typeLabel(_ argument: JSON) -> String {
  let type = text(argument, "type")
  if let values = argument["values"] as? [String] {
    return values.map { "`\($0)`" }.joined(separator: ", ")
  }
  if let range = argument["range"] as? [Int], range.count == 2 {
    return "\(type) (\(range[0]) to \(range[1]))"
  }
  if let unit = argument["unit"] as? String { return "\(type) (\(unit))" }
  return type
}

func needsLines(_ needs: JSON) -> [String] {
  var lines: [String] = []
  switch text(needs, "app") {
  case "launches": lines.append("Starts the app when it is down.")
  case "optional": lines.append("Asks the app when it is running; never starts it.")
  default: lines.append("Does not use the app.")
  }
  if needs["server"] as? Bool == true {
    lines.append("Talks to the ntfy server with the configured URL and token.")
  }
  if needs["files"] as? Bool == true {
    lines.append("Reads or writes the local config or history files.")
  }
  if let note = needs["note"] as? String { lines.append(note) }
  return lines
}

// MARK: docs/cli.md

func renderCommand(_ command: JSON, depth: Int, into lines: inout [String]) {
  let path = text(command, "path")
  lines.append(String(repeating: "#", count: min(depth, 6)) + " `\(path)`")
  lines += ["", text(command, "abstract"), ""]
  lines += ["```", text(command, "usage"), "```", ""]
  if let body = command["discussion"] as? String { lines += discussion(body) }

  let arguments = objects(command, "arguments")
  if !arguments.isEmpty {
    let rows = arguments.map { argument -> [String] in
      let short = (argument["short"] as? String).map { ", `\($0)`" } ?? ""
      let fallback = text(argument, "default")
      return [
        "`\(text(argument, "name"))`" + short,
        text(argument, "kind"),
        typeLabel(argument),
        fallback.isEmpty ? "" : "`\(fallback)`",
        argument["required"] as? Bool == true ? "yes" : "no",
        describe(argument),
      ]
    }
    lines += table(["Argument", "Kind", "Type", "Default", "Required", "Description"], rows)
    lines.append("")
  }

  let subcommands = objects(command, "subcommands")
  if depth == 2 {
    lines += ["**Needs**", ""] + needsLines(command["needs"] as? JSON ?? [:]).map { "- \($0)" }
    lines.append("")
    let errors = list(command, "errorCodes")
    let codes = (["usage"] + errors).map { "`\($0)`" }.joined(separator: ", ")
    lines += ["**Error codes:** \(codes). See [Error codes](#error-codes).", ""]
    let examples = list(command, "examples")
    if !examples.isEmpty {
      lines += ["**Examples**", "", "```sh"] + examples + ["```", ""]
    }
  }
  for subcommand in subcommands {
    renderCommand(subcommand, depth: depth + 1, into: &lines)
  }
}

var doc: [String] = [
  "# ntfy-mac CLI reference",
  "",
  "<!-- Generated by scripts/generate-cli-docs.swift from `ntfy-mac schema --json`. Do not edit; run `make docs`. -->",
  "",
  text(root, "abstract"),
  "",
]
doc += discussion(text(root, "discussion"))
doc += [
  "## Conventions",
  "",
  "- **Output:** with `--json`, stdout carries JSON and nothing else: one document per command, one per line (NDJSON) for `tail`. Without it, stdout carries text for people.",
  "- **Diagnostics:** progress, hints and warnings go to stderr, in both modes.",
  "- **Errors:** with `--json` a failure prints `{\"error\":{\"code\":\"...\",\"exitCode\":N,\"message\":\"...\"}}` on stdout and `Error: <message>` on stderr. The exit code is the one in the tables below.",
  "- **Strict flags:** an unknown flag or a bad value exits 2 and does nothing.",
  "- **Machine-readable form of this page:** `ntfy-mac schema --json`.",
  "- **Settings:** every setting the app exposes, and the command that sets it, is in [Settings](settings.md).",
  "",
  "## Exit codes",
  "",
]
doc += table(
  ["Code", "Name", "Meaning"],
  exitCodes.map { [String($0["code"] as? Int ?? -1), text($0, "name"), text($0, "meaning")] })
doc += ["", "## Error codes", ""]
doc += table(
  ["Code", "Exit", "Meaning"],
  errorCodes.map { [text($0, "code"), String($0["exitCode"] as? Int ?? -1), text($0, "meaning")] })
doc += [
  "", "## UI actions and their CLI equivalents", "",
  "Everything the History window does to a message has a command. A test fails when an action has no command here.",
  "",
]
doc += table(
  ["Action in the window", "Command", "Example", "Notes"],
  uiActions.map {
    [
      text($0, "label"), "`ntfy-mac \(text($0, "command"))`", "`\(text($0, "example"))`",
      text($0, "note"),
    ]
  })
doc += ["", "## Commands", ""]
doc += table(
  ["Command", "Description"],
  commands.map { ["[`\(text($0, "path"))`](#\(anchor(text($0, "path"))))", text($0, "abstract")] })
doc.append("")
for command in commands {
  renderCommand(command, depth: 2, into: &doc)
}
while doc.last == "" { doc.removeLast() }
let cliMarkdown = doc.joined(separator: "\n") + "\n"

// MARK: docs/settings.md

var settingsDoc: [String] = [
  "# ntfy-mac settings",
  "",
  "<!-- Generated by scripts/generate-cli-docs.swift from `ntfy-mac schema --json`. Do not edit; run `make docs`. -->",
  "",
  "Every setting the app's Settings window shows has a command. A test fails when a setting has no command here, so the two cannot drift. The same list is in `ntfy-mac schema --json` under `settings`; the commands are described in the [CLI reference](cli.md).",
  "",
  "Settings in `config.json` apply to the running app through its config watcher; no restart is needed.",
  "",
]
var groupOrder: [String] = []
for setting in settings where !groupOrder.contains(text(setting, "group")) {
  groupOrder.append(text(setting, "group"))
}
for group in groupOrder {
  let members = settings.filter { text($0, "group") == group }
  settingsDoc += ["## \(text(members[0], "groupTitle"))", ""]
  let rows = members.map { setting -> [String] in
    let key = (setting["configKey"] as? String).map { "`\($0)`" } ?? ""
    let storage = text(setting, "storageTitle") + (key.isEmpty ? "" : ": " + key)
    var command = (setting["command"] as? String).map { "`ntfy-mac \($0)`" } ?? "UI only"
    let example = (setting["example"] as? String).map { "`\($0)`" } ?? ""
    if text(setting, "kind") == "readOnly" { command += " (read only)" }
    return [text(setting, "label"), storage, command, example, text(setting, "note")]
  }
  settingsDoc += table(["Setting", "Lives in", "Command", "Example", "Notes"], rows)
  settingsDoc.append("")
}
while settingsDoc.last == "" { settingsDoc.removeLast() }
let settingsMarkdown = settingsDoc.joined(separator: "\n") + "\n"

// MARK: llms.txt

var llms: [String] = [
  "# ntfy-mac",
  "",
  "> A macOS app and CLI for ntfy servers. Notifications arrive through Notification Center; the `ntfy-mac` CLI reads and acts on the same history, so scripts and agents can publish, list, wait for a reply and acknowledge. Every command takes `--json`.",
  "",
  "ntfy-mac is a background app (`NtfyMac.app`) that holds the ntfy stream and stores every message in a local history database. The CLI is `ntfy-mac`, inside the app bundle. This file is generated from `ntfy-mac schema --json`.",
  "",
  "## Docs",
  "",
  "- [CLI reference](\(cliPage)): every command, flag, exit code and error code, with examples",
  "- [Settings](\(settingsPage)): every setting the app exposes, where it is stored and the command that sets it",
  "- [README](\(readmePage)#use-from-agents-and-scripts): install, setup and the agent quick start",
  "- [How it works](\(repository)/blob/master/docs/how-it-works.md): streaming, reconnect, delivery, history",
  "",
  "## Contract",
  "",
  "- **Machine-readable:** `ntfy-mac schema --json` prints the whole command tree on one line (schemaVersion \(schemaVersion)), keys sorted.",
  "- **stdout vs stderr:** data on stdout, diagnostics on stderr. With `--json`, stdout is JSON only.",
  "- **Success:** one JSON document per command. `ls`, `search` print an array of message objects; `read` prints one message; `status`, `doctor`, `pause`, `publish` print an object.",
  "- **Failure:** with `--json`, stdout gets `{\"error\":{\"code\":\"not-found\",\"exitCode\":1,\"message\":\"...\"}}` and stderr gets `Error: <message>`. Branch on `error.code` or on the exit code.",
  "- **Exit codes:**",
]
llms += exitCodes.map {
  "  - `\($0["code"] as? Int ?? -1)` \(text($0, "name")): \(text($0, "meaning"))"
}
llms += [
  "",
  "## Messages and tail",
  "",
  "A message object has these fields; absent values are `null`, never missing:",
  "",
  "```json",
  "{\"topic\":\"alerts\",\"id\":\"m1\",\"time\":\"2030-01-01T08:00:00Z\",\"title\":null,\"message\":\"Disk at 91%\",\"priority\":4,\"tags\":[\"warning\"],\"read\":false,\"acknowledged\":false,\"click\":null,\"attachments\":[]}",
  "```",
  "",
  "- **`tail` is NDJSON, always:** one message object per line, oldest first, with or without `--json`. `--follow` keeps polling the history every 500 ms and ends cleanly on SIGINT. A catch-up after an outage (messages older than a minute when stored) is not followed.",
  "- **`read` marks the message read** unless you pass `--no-mark`.",
  "- **`pause` with no flags** pauses until `ntfy-mac resume` (stored as 2100-01-01).",
  "",
  "## Wait for a human",
  "",
  "`wait` blocks until a message matches, so an agent can ask a question and sleep on the answer:",
  "",
  "```sh",
  "ntfy-mac publish approvals -m \"Deploy v2 to prod?\" -p 4",
  "ntfy-mac wait --topic approvals --match '/^(yes|no)/i' --timeout 600 --json",
  "```",
  "",
  "- Only messages that arrive after `wait` started count. Pick a `--match` that your own published message does not satisfy.",
  "- `--match` is a case-insensitive substring of title or message, or `/regex/` (`/regex/i` ignores case).",
  "- Exit 0 prints the matching message. Exit 1 with error code `timeout` means nobody answered; the default timeout is 300 seconds.",
  "- `--ack` acknowledges the match through the app; that is the only way `wait` starts the app.",
  "",
  "## Prerequisites",
  "",
  "- **Server and token:** run `ntfy-mac setup --url https://ntfy.example.com --token tk_...` once. The token lives in the Keychain. `publish` needs it; `not-configured` (exit 1) means setup is missing, `unauthorized` (exit 3) means the token was rejected, `server-unreachable` (exit 7) means no answer.",
  "- **The app:** it fills the history that `ls`, `search`, `read`, `tail` and `wait` read. Those read files directly and work while the app is down, but see nothing new. `ack`, `notify`, `start` and `login-item` start the app; exit 4 means it could not run or notifications are not allowed.",
  "- **Check first:** `ntfy-mac status --json` reports `configured`, `running`, `paused`, `permission` and history counts without changing anything. `ntfy-mac doctor --json` runs the full read-only health check.",
  "",
  "## Commands",
  "",
]
for command in commands {
  let path = text(command, "path")
  llms.append(
    "- [`\(text(command, "usage"))`](\(cliPage)#\(anchor(path))): \(text(command, "abstract"))")
}
llms.append("")
let llmsText = llms.joined(separator: "\n")

// MARK: Output

func write(_ content: String, to relativePath: String) {
  let url = outDirectory.appendingPathComponent(relativePath)
  do {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try content.write(to: url, atomically: true, encoding: .utf8)
  } catch {
    fail("cannot write \(url.path): \(error)")
  }
}

write(cliMarkdown, to: "docs/cli.md")
write(settingsMarkdown, to: "docs/settings.md")
write(llmsText, to: "llms.txt")
print("Wrote docs/cli.md, docs/settings.md and llms.txt to \(outDirectory.path)")
