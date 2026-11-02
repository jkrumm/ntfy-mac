import ArgumentParser

/// The option every command takes: `--json` switches stdout to machine-readable output.
struct OutputOptions: ParsableArguments {
  @Flag(name: .long, help: "Print machine-readable JSON on stdout instead of text.")
  var json = false
}

/// A subcommand. Parsing is ArgumentParser's job; `execute` is the logic, run against an
/// injected environment so tests drive it with fakes. Errors thrown out of `execute` are mapped
/// to an exit code by `CLIEntry`, nowhere else.
protocol CLICommand: AsyncParsableCommand {
  var output: OutputOptions { get }
  func execute(_ environment: CLIEnvironment, _ out: Output) async throws
}
