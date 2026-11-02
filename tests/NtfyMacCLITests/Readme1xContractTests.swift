import Foundation
import NtfyCore
import Testing

@testable import NtfyMacCLI

/// One invocation the 1.x README shows. Later steps extend `all` with their new commands.
struct ReadmeInvocation: Sendable, CustomTestStringConvertible {
  let args: [String]
  var stdin: String?
  /// Run on a terminal, answering the prompts in this order.
  var interactive: (answers: [String], secrets: [String])?
  var expectedExit: ProcessExit = .success

  var testDescription: String { "ntfy-mac " + args.joined(separator: " ") }
}

extension ReadmeInvocation {
  static let all: [ReadmeInvocation] = [
    // Setup
    ReadmeInvocation(args: ["setup"], interactive: (["ntfy.example.com"], ["tk_x"])),
    ReadmeInvocation(args: ["setup", "--url", "https://ntfy.example.com", "--token", "tk_x"]),
    // Commands table
    ReadmeInvocation(args: ["doctor"]),
    ReadmeInvocation(args: ["doctor", "--json"]),
    ReadmeInvocation(args: ["subscribe"]),
    ReadmeInvocation(args: ["subscribe", "builds"]),
    ReadmeInvocation(args: ["unsubscribe", "builds"], expectedExit: .runtime),
    ReadmeInvocation(args: ["config"]),
    ReadmeInvocation(args: ["config", "sounds"]),
    ReadmeInvocation(args: ["config", "dismiss"]),
    // Notification sounds
    ReadmeInvocation(args: ["config", "sounds", "set", "5", "Sosumi"]),
    ReadmeInvocation(args: ["config", "sounds", "set", "2", "silent"]),
    ReadmeInvocation(args: ["config", "dismiss", "set", "3", "15"]),
    ReadmeInvocation(args: ["config", "dismiss", "set", "5", "never"]),
    ReadmeInvocation(args: ["sounds"]),
    // Local notifications
    ReadmeInvocation(args: ["notify", "-m", "Deploy complete"]),
    ReadmeInvocation(args: ["notify", "-t", "Alert", "-m", "Disk usage above 90%", "-p", "5"]),
    ReadmeInvocation(args: ["notify", "-m", "Build passed", "--tag", "white_check_mark"]),
    ReadmeInvocation(args: ["notify", "-m", "Click me", "--url", "https://example.com"]),
    ReadmeInvocation(args: ["notify", "-m", "Temporary", "-d", "10"]),
    ReadmeInvocation(args: ["notify", "--json"], stdin: #"{"title":"T","body":"B"}"#),
    // Operations
    ReadmeInvocation(args: ["logs"]),
    ReadmeInvocation(args: ["logs", "--error"]),
    ReadmeInvocation(args: ["update"], expectedExit: .runtime),
    ReadmeInvocation(args: ["uninstall"], interactive: (["y"], [])),
    ReadmeInvocation(args: ["version"]),
    ReadmeInvocation(args: ["help"]),
    ReadmeInvocation(args: ["start"]),
  ]
}

@Suite struct Readme1xContractTests {
  /// Every README invocation is accepted by the parser and runs against the fakes.
  @Test(arguments: ReadmeInvocation.all)
  func invocationRuns(_ invocation: ReadmeInvocation) async throws {
    var rig = CLIRig(configured: !invocation.args.starts(with: ["setup"]))
    if let interactive = invocation.interactive {
      rig.terminal = Terminal(stdinIsTTY: true, stdoutIsTTY: true)
      rig.prompter = ScriptedPrompter(answers: interactive.answers, secrets: interactive.secrets)
    }
    rig.stdin = Data((invocation.stdin ?? "").utf8)
    let result = await rig.run(invocation.args)
    #expect(result.exit == invocation.expectedExit, "stderr: \(result.stderr)")
  }

  @Test func theTableCoversEveryDocumentedCommand() {
    let commands = Set(ReadmeInvocation.all.compactMap { $0.args.first })
    let documented: Set<String> = [
      "setup", "doctor", "subscribe", "unsubscribe", "config", "notify", "sounds", "logs",
      "update", "uninstall", "version", "help", "start",
    ]
    #expect(documented.isSubset(of: commands))
  }

  @Test(arguments: ["-v", "--version"])
  func versionFlagsPrintTheBanner(flag: String) async {
    let result = await CLIRig().run(flag)
    #expect(result.exit == .success)
    #expect(result.stdout == "ntfy-mac \(Version.current)\n")
  }

  @Test(arguments: [["--help"], ["-h"], []])
  func helpListsEveryCommand(arguments: [String]) async {
    let result = await CLIRig().run(arguments)
    #expect(result.exit == .success)
    for command in ReadmeInvocation.all.compactMap({ $0.args.first }) where command != "help" {
      #expect(result.stdout.contains(command), "help is missing \(command)")
    }
  }
}
