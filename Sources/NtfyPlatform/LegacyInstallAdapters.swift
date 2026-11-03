import Darwin
import Foundation
import NtfyCore
import Synchronization

/// Runs a system tool to completion off the cooperative pool and returns its stdout.
enum SystemTool {
  private struct Outcome: Sendable {
    let status: Int32
    let output: Data
    let timedOut: Bool
  }

  /// - Parameter timeout: Seconds after which the tool is killed and the call fails; nil waits
  ///   as long as the tool runs.
  static func run(
    _ executable: String, _ arguments: [String], timeout: Double? = nil
  ) async throws(NtfyError) -> (status: Int32, output: Data) {
    let outcome: Outcome
    do {
      outcome = try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global().async {
          let process = Process()
          let pipe = Pipe()
          process.executableURL = URL(fileURLWithPath: executable)
          process.arguments = arguments
          process.standardOutput = pipe
          process.standardError = FileHandle.nullDevice
          do {
            try process.run()
          } catch {
            continuation.resume(throwing: error)
            return
          }
          let expired = Mutex(false)
          let watchdog = DispatchWorkItem {
            expired.withLock { $0 = true }
            process.terminate()
            // A tool that ignores SIGTERM would keep the read below open.
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
              if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
          }
          if let timeout {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
          }
          // Drain before waiting: a full pipe would block the tool forever.
          let output = pipe.fileHandleForReading.readDataToEndOfFile()
          process.waitUntilExit()
          watchdog.cancel()
          continuation.resume(
            returning: Outcome(
              status: process.terminationStatus, output: output, timedOut: expired.withLock { $0 }))
        }
      }
    } catch {
      throw .storage("cannot run \(executable): \(error.localizedDescription)")
    }
    guard !outcome.timedOut else { throw .storage("\(executable) timed out and was stopped") }
    return (outcome.status, outcome.output)
  }
}

/// `launchctl` for the user's GUI domain.
public struct LaunchctlAgents: LaunchAgentManaging {
  private static let executable = "/bin/launchctl"
  private static let timeout = 10.0

  public init() {}

  public func isLoaded(label: String, uid: UInt32) async -> Bool {
    let result = try? await SystemTool.run(
      Self.executable, ["print", "gui/\(uid)/\(label)"], timeout: Self.timeout)
    return result?.status == 0
  }

  public func bootout(label: String, uid: UInt32) async throws(NtfyError) {
    let result = try await SystemTool.run(
      Self.executable, ["bootout", "gui/\(uid)/\(label)"], timeout: Self.timeout)
    guard result.status == 0 else {
      throw .storage("launchctl bootout \(label) exited with \(result.status)")
    }
  }
}

/// The LaunchAgent plists of a directory, parsed as property lists.
public struct LaunchAgentPlistFiles: LaunchAgentPlistReading {
  /// A real LaunchAgent plist is a few hundred bytes; anything bigger is not worth parsing.
  private static let maxBytes = 1_000_000

  public init() {}

  public func plists(in directory: URL) -> [LaunchAgentPlist] {
    let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
    return names.filter { $0.hasSuffix(".plist") }.sorted().compactMap { name in
      let file = directory.appending(path: name, directoryHint: .notDirectory)
      guard
        let size = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.size]
          as? Int, size <= Self.maxBytes,
        let data = try? Data(contentsOf: file),
        let root = try? PropertyListSerialization.propertyList(from: data, format: nil)
          as? [String: Any]
      else { return nil }
      let arguments = root["ProgramArguments"] as? [String]
      return LaunchAgentPlist(
        file: file, label: root["Label"] as? String,
        program: arguments?.first ?? root["Program"] as? String)
    }
  }
}

/// `lsregister`, the Launch Services database tool.
public struct LSRegister: LaunchServicesRegistering {
  static let executable =
    "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  /// The full dump takes a few seconds on a busy database.
  private static let timeout = 30.0

  public init() {}

  public func registeredHelperPaths() async throws(NtfyError) -> [String] {
    let result = try await SystemTool.run(Self.executable, ["-dump"], timeout: Self.timeout)
    guard result.status == 0 else {
      throw .storage("lsregister -dump exited with \(result.status)")
    }
    return Self.helperPaths(inDump: String(bytes: result.output, encoding: .utf8) ?? "")
  }

  /// The `path:` lines of a dump read `path:<spaces><path> (0x<id>)`; the path may hold spaces.
  static func helperPaths(inDump dump: String) -> [String] {
    var paths: Set<String> = []
    for line in dump.split(separator: "\n") where line.hasPrefix("path:") {
      var path = String(line.dropFirst("path:".count).drop { $0 == " " })
      if path.hasSuffix(")"), let id = path.range(of: " (0x", options: .backwards) {
        path = String(path[..<id.lowerBound])
      }
      if path.hasSuffix("/ntfy-notify.app") { paths.insert(path) }
    }
    return paths.sorted()
  }

  public func unregister(path: String) async throws(NtfyError) {
    let result = try await SystemTool.run(Self.executable, ["-u", path], timeout: Self.timeout)
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

  public func terminate(_ pid: Int32, expectedPath: String) async throws(NtfyError) {
    guard kill(pid, SIGTERM) == 0 else {
      if errno == ESRCH { return }
      throw .storage("cannot signal pid \(pid): errno \(errno)")
    }
    for _ in 0..<30 {
      if kill(pid, 0) != 0 { return }
      try? await Task.sleep(for: .milliseconds(100))
    }
    // The pid could have been reused while we waited; only the same executable gets SIGKILL.
    guard executablePath(of: pid) == expectedPath else { return }
    kill(pid, SIGKILL)
    try? await Task.sleep(for: .milliseconds(200))
    if kill(pid, 0) == 0, executablePath(of: pid) == expectedPath {
      throw .storage("pid \(pid) survived SIGKILL")
    }
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
      plists: LaunchAgentPlistFiles(),
      runningExecutable: runningExecutable, processID: getpid())
  }
}
