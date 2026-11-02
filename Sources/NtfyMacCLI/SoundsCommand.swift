import ArgumentParser
import Foundation
import NtfyPlatform

struct SoundsCommand: CLICommand {
  static let configuration = CommandConfiguration(
    commandName: "sounds", abstract: "Preview the notification sounds.")

  @Argument(help: "Only sounds whose name contains this text.") var filter: String?
  @OptionGroup var output: OutputOptions

  private struct Report: Encodable {
    let sounds: [String]
  }

  func execute(_ environment: CLIEnvironment, _ out: Output) async throws {
    let all = SoundCatalog.sounds(in: environment.paths.soundDirectories)
    let matching =
      filter.map { text in
        all.filter { $0.name.lowercased().contains(text.lowercased()) }
      } ?? all
    guard !matching.isEmpty else {
      throw CLIFailure.runtime(
        "no-match",
        "No sound matching \"\(filter ?? "")\". Available: \(all.map(\.name).joined(separator: ", "))"
      )
    }
    if out.json {
      out.document(Report(sounds: matching.map(\.name)))
      return
    }
    for sound in matching {
      out.line("Playing: \(sound.name)")
      let status = try await environment.processes.run(
        "/usr/bin/afplay", [sound.file.path], output: .stderr)
      if status != 0 { out.note("Could not play \(sound.name) (afplay exit \(status)).") }
    }
  }
}
