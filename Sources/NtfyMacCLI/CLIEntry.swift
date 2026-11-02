import ArgumentParser
import Foundation

/// Runs one invocation end to end and returns the exit status. Parse errors, command errors and
/// help all end here, so this is the only place that turns errors into exit codes.
enum CLIEntry {
  static func run(
    _ arguments: [String], environment: CLIEnvironment, makeOutput: (Bool) -> Output
  ) async -> ProcessExit {
    let arguments = normalized(arguments)
    let command: any ParsableCommand
    do {
      command = try NtfyMac.parseAsRoot(arguments)
    } catch {
      return reportParseFailure(error, out: makeOutput(arguments.contains("--json")))
    }
    guard let runnable = command as? any CLICommand else {
      return await runBuiltIn(command, out: makeOutput(false))
    }
    let out = makeOutput(runnable.output.json)
    do {
      try await runnable.execute(environment, out)
      return .success
    } catch let request as ExitRequest {
      return request.exit
    } catch {
      let report = ErrorReport(error)
      out.fail(report)
      return ProcessExit(error: error)
    }
  }

  /// The root command and ArgumentParser's `help` subcommand only ask for help, by throwing.
  private static func runBuiltIn(_ command: any ParsableCommand, out: Output) async -> ProcessExit {
    do {
      if var asynchronous = command as? any AsyncParsableCommand {
        try await asynchronous.run()
      } else {
        var synchronous = command
        try synchronous.run()
      }
      return .success
    } catch {
      return reportParseFailure(error, out: out)
    }
  }

  /// `-v` and `--version` are the `version` command, as in 1.x.
  private static func normalized(_ arguments: [String]) -> [String] {
    guard let first = arguments.first, first == "-v" || first == "--version" else {
      return arguments
    }
    return ["version"] + arguments.dropFirst()
  }

  /// Help and `--version` requests are not failures. Everything else ArgumentParser rejects is a
  /// usage error, exit 2 (its own default would be 64).
  private static func reportParseFailure(_ error: any Error, out: Output) -> ProcessExit {
    if NtfyMac.exitCode(for: error) == .success {
      out.raw(NtfyMac.fullMessage(for: error))
      return .success
    }
    let message = NtfyMac.message(for: error)
    if out.json {
      out.fail(ErrorReport(code: "usage", message: message, exit: .usage))
    } else {
      out.note(NtfyMac.fullMessage(for: error))
    }
    return .usage
  }
}
