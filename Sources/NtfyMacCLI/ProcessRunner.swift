import Foundation
import NtfyCore

/// Where a child process's stdout goes.
enum ChildOutput: Sendable {
  /// Our stdout; for commands whose output is the result (`log`).
  case inherit
  /// Our stderr; for progress of a command whose stdout must stay clean (`brew`).
  case stderr
}

protocol ProcessRunning: Sendable {
  /// Runs to completion and returns the exit status.
  func run(_ executable: String, _ arguments: [String], output: ChildOutput) async throws(NtfyError)
    -> Int32
}

struct SystemProcessRunner: ProcessRunning {
  func run(
    _ executable: String, _ arguments: [String], output: ChildOutput
  ) async throws(NtfyError) -> Int32 {
    do {
      return try await withCheckedThrowingContinuation { continuation in
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if case .stderr = output { process.standardOutput = FileHandle.standardError }
        process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
        do {
          try process.run()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    } catch {
      throw .storage("cannot run \(executable): \(error.localizedDescription)")
    }
  }
}
