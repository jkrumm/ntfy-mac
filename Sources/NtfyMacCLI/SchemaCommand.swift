import ArgumentParser
import Foundation

struct SchemaCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "schema", abstract: "Describe every command, flag, exit code and error code.",
    discussion: """
      With --json: one document with the full command tree (arguments with type, default, range,
      required, repeatable; what each command needs from the app, server and files; its error
      codes) plus the stable exit and error code lists. Keys are sorted, so the output is
      deterministic. Without --json: a compact usage listing.
      """)

  @OptionGroup var output: OutputOptions

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let schema: SchemaDocument
    do {
      schema = try SchemaBuilder.build(root: NtfyMac.self)
    } catch {
      throw CLIFailure.runtime("error", "Cannot read the command definitions: \(error)")
    }
    out.result(schema, text: schema.compactText())
  }
}
