import Foundation

/// What a cleanup found and did. Entries read `<what>: <path or label>`.
public struct LegacyCleanupReport: Codable, Sendable, Equatable {
  /// Everything the 1.x install had left, at the start.
  public var found: [String] = []
  public var removed: [String] = []
  public var failed: [String] = []

  public init(found: [String] = [], removed: [String] = [], failed: [String] = []) {
    self.found = found
    self.removed = removed
    self.failed = failed
  }

  public var isEmpty: Bool { found.isEmpty && removed.isEmpty && failed.isEmpty }
}

/// Removes the artifacts of a 1.x install (Bun daemon, `ntfy-notify.app` helper, LaunchAgent or
/// brew service). Best effort and idempotent: a step that fails is reported and the rest still
/// run; nothing throws. `config.json` and `state.json` are never touched.
public struct LegacyInstallCleanup: Sendable {
  public enum Scope: Sendable {
    /// Files, services and the daemon: cheap, no Launch Services scan.
    case quick
    /// Also scans the Launch Services database for helper registrations (slow).
    case full
  }

  private enum Artifact {
    case service(label: String, plist: URL, loaded: Bool)
    case daemon(pid: Int32)
    case file(kind: String, url: URL)
    case registration(path: String)

    var title: String {
      switch self {
      case .service(let label, let plist, _): "launch agent \(label): \(plist.path)"
      case .daemon(let pid): "1.x daemon: pid \(pid)"
      case .file(let kind, let url): "\(kind): \(url.path)"
      case .registration(let path): "Launch Services entry: \(path)"
      }
    }
  }

  private let layout: LegacyInstallLayout
  private let agents: any LaunchAgentManaging
  private let registry: any LaunchServicesRegistering
  private let processes: any LegacyProcessTerminating
  private let plists: any LaunchAgentPlistReading
  private let runningExecutable: URL?
  private let processID: Int32

  /// - Parameters:
  ///   - plists: Finds a brew service under a label other than the known ones.
  ///   - runningExecutable: The executable doing the cleanup; never removed.
  ///   - processID: The cleaning process; never signalled.
  public init(
    layout: LegacyInstallLayout, agents: any LaunchAgentManaging,
    registry: any LaunchServicesRegistering, processes: any LegacyProcessTerminating,
    plists: any LaunchAgentPlistReading = NoLaunchAgentPlists(),
    runningExecutable: URL?, processID: Int32
  ) {
    self.layout = layout
    self.agents = agents
    self.registry = registry
    self.processes = processes
    self.plists = plists
    self.runningExecutable = runningExecutable?.resolvingSymlinksInPath()
    self.processID = processID
  }

  /// What exists, without changing anything.
  public func detect(scope: Scope = .full) async -> LegacyCleanupReport {
    let (artifacts, scanFailure) = await inventory(scope)
    return LegacyCleanupReport(
      found: artifacts.map(\.title), failed: scanFailure.map { [$0] } ?? [])
  }

  /// Removes everything `detect` lists.
  public func run(scope: Scope = .full) async -> LegacyCleanupReport {
    let (artifacts, scanFailure) = await inventory(scope)
    var report = LegacyCleanupReport(found: artifacts.map(\.title))
    if let scanFailure { report.failed.append(scanFailure) }
    for artifact in artifacts {
      do throws(NtfyError) {
        try await remove(artifact)
        report.removed.append(artifact.title)
      } catch {
        report.failed.append("\(artifact.title) (\(error))")
      }
    }
    return report
  }

  // MARK: Inventory

  private func inventory(_ scope: Scope) async -> ([Artifact], String?) {
    var artifacts = await services()
    let daemon = legacyDaemon()
    if let daemon { artifacts.append(.daemon(pid: daemon.pid)) }
    artifacts += existing(
      [("curl helper app", layout.curlHelper), ("dev helper app", layout.devHelper)]
        + layout.brewHelpers().map { ("brew helper app", $0) })
    if isRemovableCurlBinary() {
      artifacts.append(.file(kind: "curl binary", url: layout.curlBinary))
    }
    artifacts += existing(layout.logs.map { ("log", $0) })
    // With a live daemon the pid file goes only after it has been stopped.
    let pidFile = daemon == nil ? [("pid file", layout.pidFile)] : []
    artifacts += existing(pidFile + temporaryFiles().map { ("temporary file", $0) })
    guard scope == .full else { return (artifacts, nil) }
    do throws(NtfyError) {
      let paths = try await registry.registeredHelperPaths()
      return (artifacts + Set(paths).sorted().map { .registration(path: $0) }, nil)
    } catch {
      return (artifacts, "Launch Services scan (\(error))")
    }
  }

  /// The curl agent and both brew service labels, by label and file name; then any other plist
  /// whose program is the formula's `ntfy-mac`. A plist that is neither is never listed.
  private func services() async -> [Artifact] {
    var artifacts: [Artifact] = []
    var listed: Set<String> = []
    for label in [LegacyInstallLayout.curlLabel] + LegacyInstallLayout.brewLabels {
      let plist = layout.plist(label: label)
      listed.insert(plist.standardized.path)
      let loaded = await agents.isLoaded(label: label, uid: layout.uid)
      if loaded || LegacyFiles.exists(plist) {
        artifacts.append(.service(label: label, plist: plist, loaded: loaded))
      }
    }
    let candidates = plists.plists(in: layout.launchAgents).sorted { $0.file.path < $1.file.path }
    for candidate in candidates {
      guard
        let program = candidate.program, layout.isFormulaProgram(program),
        listed.insert(candidate.file.standardized.path).inserted
      else { continue }
      let label = Self.serviceLabel(of: candidate)
      let loaded = await agents.isLoaded(label: label, uid: layout.uid)
      artifacts.append(.service(label: label, plist: candidate.file, loaded: loaded))
    }
    return artifacts
  }

  /// The plist's `Label`, or the file name without `.plist` when it has none or one that could
  /// not be a plain `gui/<uid>/<label>` target.
  private static func serviceLabel(of plist: LaunchAgentPlist) -> String {
    if let label = plist.label, !label.isEmpty, !label.contains("/"),
      label.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
    {
      return label
    }
    return plist.file.deletingPathExtension().lastPathComponent
  }

  private func existing(_ items: [(String, URL)]) -> [Artifact] {
    items.filter { LegacyFiles.exists($0.1) }.map { .file(kind: $0.0, url: $0.1) }
  }

  /// The pid file's process, only when its executable proves it is the 1.x binary: named
  /// `ntfy-mac`, outside any `.app` (the 2.0 binary lives in `NtfyMac.app`), and not us.
  private func legacyDaemon() -> (pid: Int32, path: String)? {
    guard
      let text = try? String(contentsOf: layout.pidFile, encoding: .utf8),
      let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)),
      pid > 1, pid != processID,
      let path = processes.executablePath(of: pid)
    else { return nil }
    let executable = URL(fileURLWithPath: path).resolvingSymlinksInPath()
    guard executable != runningExecutable else { return nil }
    guard executable.lastPathComponent == "ntfy-mac", !executable.path.contains(".app/") else {
      return nil
    }
    return (pid, path)
  }

  private func isRemovableCurlBinary() -> Bool {
    guard LegacyFiles.isRegularMachO(layout.curlBinary) else { return false }
    return layout.curlBinary.resolvingSymlinksInPath() != runningExecutable
  }

  /// `*.tmp` files 1.x left in the state directory. Hidden ones are 2.0's own atomic writes.
  private func temporaryFiles() -> [URL] {
    let names =
      (try? FileManager.default.contentsOfDirectory(atPath: layout.stateDirectory.path)) ?? []
    return names.sorted().filter { $0.hasSuffix(".tmp") && !$0.hasPrefix(".") }.map {
      layout.stateDirectory.appending(path: $0, directoryHint: .notDirectory)
    }
  }

  // MARK: Removal

  private func remove(_ artifact: Artifact) async throws(NtfyError) {
    switch artifact {
    case .service(let label, let plist, let loaded):
      if loaded { try await bootoutIfStillLoaded(label) }
      try delete(plist)
    case .daemon(let pid):
      // Launchd may have ended it already, and the pid may have been reused since the scan.
      if let daemon = legacyDaemon(), daemon.pid == pid {
        try await processes.terminate(pid, expectedPath: daemon.path)
      }
      try delete(layout.pidFile)
    case .file(_, let url):
      try delete(url)
    case .registration(let path):
      try await registry.unregister(path: path)
    }
  }

  /// A service that went away between the scan and the bootout (the 1.x daemon stopping
  /// itself, a brew upgrade) is not a failure.
  private func bootoutIfStillLoaded(_ label: String) async throws(NtfyError) {
    do throws(NtfyError) {
      try await agents.bootout(label: label, uid: layout.uid)
    } catch {
      if await agents.isLoaded(label: label, uid: layout.uid) { throw error }
    }
  }

  private func delete(_ url: URL) throws(NtfyError) {
    guard LegacyFiles.exists(url) else { return }
    do {
      try FileManager.default.removeItem(at: url)
    } catch {
      throw .storage("cannot remove \(url.path): \(error.localizedDescription)")
    }
  }
}
