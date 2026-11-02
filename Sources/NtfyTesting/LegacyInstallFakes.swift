import NtfyCore
import Synchronization

/// launchd with a set of loaded labels; remembers every `bootout`.
public final class InMemoryLaunchAgents: LaunchAgentManaging {
  private struct State {
    var loaded: Set<String>
    var bootouts: [String] = []
  }
  private let state: Mutex<State>
  private let failing: Set<String>

  /// - Parameter failing: Labels whose `bootout` throws.
  public init(loaded: Set<String> = [], failing: Set<String> = []) {
    state = Mutex(State(loaded: loaded))
    self.failing = failing
  }

  public var bootouts: [String] { state.withLock { $0.bootouts } }

  public func isLoaded(label: String, uid: UInt32) -> Bool {
    state.withLock { $0.loaded.contains(label) }
  }

  public func bootout(label: String, uid: UInt32) throws(NtfyError) {
    if failing.contains(label) { throw .storage("bootout \(label) refused") }
    state.withLock {
      $0.bootouts.append(label)
      $0.loaded.remove(label)
    }
  }
}

/// A Launch Services database holding a list of paths.
public final class InMemoryLaunchServices: LaunchServicesRegistering {
  private struct State {
    var registered: [String]
    var unregistered: [String] = []
  }
  private let state: Mutex<State>
  private let failing: Set<String>
  private let scanFails: Bool

  /// - Parameters:
  ///   - failing: Paths whose `unregister` throws.
  ///   - scanFails: The dump itself throws.
  public init(registered: [String] = [], failing: Set<String> = [], scanFails: Bool = false) {
    state = Mutex(State(registered: registered))
    self.failing = failing
    self.scanFails = scanFails
  }

  public var unregistered: [String] { state.withLock { $0.unregistered } }

  public func registeredHelperPaths() throws(NtfyError) -> [String] {
    if scanFails { throw .storage("lsregister dump failed") }
    return state.withLock { $0.registered }
  }

  public func unregister(path: String) throws(NtfyError) {
    if failing.contains(path) { throw .storage("unregister \(path) refused") }
    state.withLock {
      $0.registered.removeAll { $0 == path }
      $0.unregistered.append(path)
    }
  }
}

/// Processes by pid with a known executable path; remembers who was terminated.
/// A pid listed in `surviving` outlives `terminate`, which then throws.
public final class InMemoryLegacyProcesses: LegacyProcessTerminating {
  private struct State {
    var running: [Int32: String]
    var terminated: [Int32] = []
  }
  private let state: Mutex<State>
  private let surviving: Set<Int32>

  public init(running: [Int32: String] = [:], surviving: Set<Int32> = []) {
    state = Mutex(State(running: running))
    self.surviving = surviving
  }

  public var terminated: [Int32] { state.withLock { $0.terminated } }

  public func executablePath(of pid: Int32) -> String? { state.withLock { $0.running[pid] } }

  public func terminate(_ pid: Int32, expectedPath: String) throws(NtfyError) {
    let signalled = state.withLock { state -> Bool in
      guard state.running[pid] == expectedPath else { return false }
      state.terminated.append(pid)
      if !surviving.contains(pid) { state.running[pid] = nil }
      return true
    }
    if signalled, surviving.contains(pid) { throw .storage("pid \(pid) survived SIGKILL") }
  }
}
