import Foundation
import NtfyCore
import Testing

@testable import NtfyMacCLI

@Suite struct SchemaTests {
  private func schema(_ rig: CLIRig = CLIRig()) async throws -> [String: Any] {
    try await rig.run("schema", "--json").json()
  }

  private func commands(_ document: [String: Any]) throws -> [[String: Any]] {
    try #require(document["commands"] as? [[String: Any]])
  }

  private func command(_ name: String, in document: [String: Any]) throws -> [String: Any] {
    try #require(try commands(document).first { $0["name"] as? String == name })
  }

  private func argument(_ name: String, of command: [String: Any]) throws -> [String: Any] {
    let arguments = try #require(command["arguments"] as? [[String: Any]])
    return try #require(arguments.first { $0["name"] as? String == name })
  }

  // MARK: Completeness

  @Test func everyRegisteredCommandHasASpecAndEverySpecACommand() throws {
    let registered = Set(try SchemaBuilder.commandNames(NtfyMac.self))
    let specified = Set(CommandSpec.all.map(\.name))
    #expect(registered.subtracting(specified).isEmpty, "commands without a spec")
    #expect(specified.subtracting(registered).isEmpty, "specs without a command")
    #expect(CommandSpec.all.count == specified.count, "duplicate spec")
  }

  @Test func everySpecArgumentNamesARealArgumentOfItsCommand() throws {
    let document = try SchemaBuilder.build(root: NtfyMac.self)
    func names(_ command: CommandSchema) -> Set<String> {
      Set(command.arguments.map(\.name)).union(command.subcommands.flatMap(names))
    }
    for spec in CommandSpec.all {
      let command = try #require(document.commands.first { $0.name == spec.name })
      let known = names(command)
      for key in spec.domains.keys {
        #expect(known.contains(key), "\(spec.name): no argument \(key)")
      }
    }
  }

  @Test func specErrorCodesAreInTheCatalog() {
    let catalog = Set(ErrorCatalog.errors.map(\.code))
    for spec in CommandSpec.all {
      #expect(catalog.isSuperset(of: spec.errors), "\(spec.name): \(spec.errors)")
    }
    #expect(catalog.count == ErrorCatalog.errors.count, "duplicate error code")
  }

  @Test func theCatalogCoversEveryCoreErrorAndExitCode() {
    let errors: [NtfyError] = [
      .unauthorized, .serverUnreachable, .rateLimited(retryAfter: nil), .redirected,
      .insecureServer, .invalidTopic("x"), .appUnavailable, .permissionDenied,
      .invalidResponse("x"), .storage("x"),
    ]
    for error in errors {
      let entry = ErrorCatalog.errors.first { $0.code == error.code }
      #expect(entry?.exitCode == ProcessExit(error: error).rawValue)
    }
    for exit in ProcessExit.allCases {
      #expect(ErrorCatalog.exitMeanings[exit] != nil)
    }
  }

  // MARK: Determinism

  @Test func theOutputIsByteIdenticalAcrossRuns() async {
    let first = await CLIRig().run("schema", "--json")
    let second = await CLIRig().run("schema", "--json")
    #expect(first.exit == .success)
    #expect(first.stdout == second.stdout)
    #expect(first.stdoutLines.count == 1)
    #expect(first.stderr.isEmpty)
  }

  @Test func keysAreSorted() async throws {
    let line = try #require(await CLIRig().run("schema", "--json").stdoutLines.first)
    let first = try #require(line.range(of: "\"abstract\""))
    let last = try #require(line.range(of: "\"version\""))
    #expect(first.lowerBound < last.lowerBound)
    #expect(line.hasPrefix("{\"abstract\":"))
  }

  // MARK: Content

  @Test func theDocumentListsEveryCommandWithItsArguments() async throws {
    let document = try await schema()
    #expect(document["schemaVersion"] as? Int == 1)
    #expect(document["version"] as? String == Version.current)
    let names = try commands(document).compactMap { $0["name"] as? String }
    for name in [
      "setup", "doctor", "notify", "status", "ls", "search", "read", "ack", "tail", "wait",
      "publish", "pause", "resume", "login-item", "schema",
    ] {
      #expect(names.contains(name), Comment(rawValue: name))
    }
    #expect(!names.contains("help"))
  }

  @Test func optionsCarryTypeDefaultRangeAndRequirement() async throws {
    let document = try await schema()
    let listing = try command("ls", in: document)
    let limit = try argument("--limit", of: listing)
    #expect(limit["kind"] as? String == "option")
    #expect(limit["type"] as? String == "integer")
    #expect(limit["default"] as? String == "20")
    #expect(limit["range"] as? [Int] == [1, 1000])
    #expect(limit["required"] as? Bool == false)
    let unread = try argument("--unread", of: listing)
    #expect(unread["kind"] as? String == "flag")
    #expect(unread["type"] as? String == "boolean")

    let wait = try command("wait", in: document)
    #expect(try argument("--match", of: wait)["required"] as? Bool == true)
    #expect(try argument("--timeout", of: wait)["unit"] as? String == "seconds")

    let publish = try command("publish", in: document)
    #expect(try argument("--tag", of: publish)["repeatable"] as? Bool == true)
    #expect(try argument("--message", of: publish)["short"] as? String == "-m")
    #expect(try argument("topic", of: publish)["kind"] as? String == "positional")

    let loginItem = try command("login-item", in: document)
    let action = try argument("action", of: loginItem)
    #expect(action["values"] as? [String] == ["off", "on", "status"])
  }

  @Test func needsAndErrorCodesDescribeEachCommand() async throws {
    let document = try await schema()
    let wait = try command("wait", in: document)
    let needs = try #require(wait["needs"] as? [String: Any])
    #expect(needs["app"] as? String == "launches")
    #expect(needs["note"] as? String == "Starts the app only with --ack.")
    #expect((wait["errorCodes"] as? [String])?.contains("timeout") == true)
    let publish = try #require(try command("publish", in: document)["needs"] as? [String: Any])
    #expect(publish["server"] as? Bool == true)
    let listing = try #require(try command("ls", in: document)["needs"] as? [String: Any])
    #expect(listing["app"] as? String == "none")
    #expect(listing["files"] as? Bool == true)
  }

  @Test func subcommandsAreNestedWithTheirOwnArguments() async throws {
    let config = try command("config", in: try await schema())
    let sounds = try #require(
      (config["subcommands"] as? [[String: Any]])?.first { $0["name"] as? String == "sounds" })
    let set = try #require(
      (sounds["subcommands"] as? [[String: Any]])?.first { $0["name"] as? String == "set" })
    #expect(set["path"] as? String == "ntfy-mac config sounds set")
    #expect(try argument("priority", of: set)["range"] as? [Int] == [1, 5])
  }

  @Test func exitAndErrorCodesAreTheStableLists() async throws {
    let document = try await schema()
    let exits = try #require(document["exitCodes"] as? [[String: Any]])
    #expect(exits.compactMap { $0["code"] as? Int } == [0, 1, 2, 3, 4, 7])
    let errors = try #require(document["errorCodes"] as? [[String: Any]])
    let timeout = try #require(errors.first { $0["code"] as? String == "timeout" })
    #expect(timeout["exitCode"] as? Int == 1)
  }

  @Test func textModeIsACompactUsageListing() async {
    let result = await CLIRig().run("schema")
    #expect(result.exit == .success)
    #expect(result.stdout.contains("[--limit <integer>]"))
    #expect(result.stdout.contains("ntfy-mac wait --topic <string> --match <string>"))
    #expect(result.stdout.contains("ntfy-mac login-item <off|on|status>"))
    #expect(result.stdout.contains("  7  serverUnreachable:"))
  }
}
