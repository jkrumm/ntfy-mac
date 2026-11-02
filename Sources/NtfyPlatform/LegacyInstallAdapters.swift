import Darwin
import Foundation
import NtfyCore

/// Runs a system tool to completion off the cooperative pool and returns its stdout.
enum SystemTool {
  static func run(
    _ executable: String, _ arguments: [String]
  ) async throws(NtfyError) -> (status: Int32, output: Data) {
    do {
      return try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
          let process = Process()
          let pipe = Pipe()
          process.executableURL = URL(fileURLWithPath: executable)
          process.arguments = arguments
          process.standardOutput = pipe
          process.standardError = FileHandle.nullDevice
          do {
            try process.run()
            // Drain before waiting: a full pipe would block the tool forever.
            let output = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            continuation.resume(returning: (process.terminationStatus, output))
          } catch {
            continuation.resume(throwing: error)
          }
        }
      }
    } catch {
      throw .storage("cannot run \(executable): \(error.localizedDescription)")
    }
  }
}

/// `launchctl` for the user's GUI domain.
public struct LaunchctlAgents: LaunchAgentManaging {
  private static let executable = "/bin/launchctl"

  public init() {}

  public func isLoaded(label: String, uid: UInt32) async -> Bool {
    let result = try? await SystemTool.run(Self.executable, ["print", "gui/\(uid)/\(label)"])
    return result?.status == 0
  }

  public func bootout(label: String, uid: UInt32) async throws(NtfyError) {
    let result = try await SystemTool.run(Self.executable, ["bootout", "gui/\(uid)/\(label)"])
    guard result.status == 0 else {
      throw .storage("launchctl bootout \(label) exited with \(result.status)")
    }
  }
}

/// `lsregister`, the Launch Services database tool.
public struct LSRegister: LaunchServicesRegistering {
  static let executable =
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

  public init() {}

  public func registeredHelperPaths() async throws(NtfyError) -> [String] {
    let result = try await SystemTool.run(Self.executable, ["-dump"])
    guard result.status == 0 else {
      throw .storage("lsregister -dump exited with \(result.status)")
    }
    let dump = String(bytes: result.output, encoding: .utf8) ?? ""
    let helper = #/\/[^ \n]*ntfy-notify\.app/#
    return Set(dump.matches(of: helper).map { String($0.output) }).sorted()
  }

  public func unregister(path: String) async throws(NtfyError) {
    let result = try await SystemTool.run(Self.executable, ["-u", path])
    guard result.status == 0 else { throw .storage("lsregister -u exited with \(result.status)") }
  }
}

/// Process inspection by pid, and a polite stop: SIGTERM, then SIGKILL if it lingers.
public struct SystemProcesses: LegacyProcessTerminating {
  public init() {}

  public func executablePath(of pid: Int32) -> String? {
    var buffer = [CChar](repeating: 0, count: 4096)
    let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
    guard length > 0 else { return nil }
    return String(
      validating: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
  }

  public func terminate(_ pid: Int32) async throws(NtfyError) {
    guard kill(pid, SIGTERM) == 0 else {
      if errno == ESRCH { return }
      throw .storage("cannot signal pid \(pid): errno \(errno)")
    }
    for _ in 0..<30 {
      if kill(pid, 0) != 0 { return }
      try? await Task.sleep(for: .milliseconds(100))
    }
    kill(pid, SIGKILL)
  }
}

extension LegacyInstallCleanup {
  /// The production wiring, rooted at `home`.
  public static func live(
    home: URL, stateDirectory: URL? = nil, runningExecutable: URL?
  ) -> LegacyInstallCleanup {
    LegacyInstallCleanup(
      layout: LegacyInstallLayout(home: home, uid: getuid(), stateDirectory: stateDirectory),
      agents: LaunchctlAgents(), registry: LSRegister(), processes: SystemProcesses(),
      runningExecutable: runningExecutable, processID: getpid())
  }
}
