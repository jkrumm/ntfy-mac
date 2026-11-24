import Foundation

/// The reconnect policy as a pure state machine: no clock, no I/O, no tasks.
///
/// The driver feeds it `Input`s together with the current time, runs the returned `Command`,
/// and calls `.timerFired` once `wakeUp` has passed.
///
/// | State | Leaves on |
/// |-|-|
/// | stopped | `start`, `restart` -> connecting / offline / paused |
/// | connecting | `opened` or activity -> connected; failure or `connectTimeout` -> backingOff / halted |
/// | connected | failure, clean finish or watchdog stall -> backingOff / halted |
/// | backingOff | `timerFired` at `until` -> connecting |
/// | offline | `pathChanged(online: true)`, or the probe after `parkedProbe` -> connecting |
/// | paused | `didWake`, `screensDidWake`, or the probe after `parkedProbe` -> connecting |
/// | halted | `restart` or `stop` only |
///
/// `didWake`, `screensDidWake` and a returning network path connect at once and skip any backoff;
/// `willSleep` and a lost path cancel the connection without counting a failure.
///
/// A parked state never waits on one event alone. A Mac in a dark-wake loop (lid closed, woken
/// every minute) is awake for seconds at a time and may report the wake after the sleep, or not
/// at all, so `paused` and `offline` carry a `wakeUp` too: the timer runs on a clock that keeps
/// counting through sleep, so it firing means the process is running again, and a connection is
/// tried. `offline` keeps its own record of the path, so the probe does not hide a later return.
public struct ReconnectMachine: Sendable {
  public struct Timing: Sendable, Hashable {
    /// First retry delay, before jitter. It doubles per consecutive failure.
    public var initialBackoff: TimeInterval = 5
    public var maxBackoff: TimeInterval = 300
    /// A connection that stayed up this long after `open` counts as healthy; only then does the
    /// failure count reset.
    public var healthyAfter: TimeInterval = 60
    /// Delay before reconnecting after a server close that followed a healthy connection.
    public var cleanFinishDelay: TimeInterval = 1
    /// Silence tolerated while connected: `max(floor, 2 * largest gap seen)`, at most `cap`.
    public var watchdogFloor: TimeInterval = 90
    public var watchdogCap: TimeInterval = 900
    /// How long an attempt may take before it has shown any sign of life.
    public var connectTimeout: TimeInterval = 90
    /// A 429 waits at least this long, and the server's Retry-After if longer, at most the cap.
    public var rateLimitFloor: TimeInterval = 60
    public var rateLimitCap: TimeInterval = 3600
    /// How long `paused` and `offline` wait for their event before a connection is tried anyway.
    public var parkedProbe: TimeInterval = 60

    public init() {}
  }

  public enum Input: Sendable, Hashable {
    case start
    case stop
    /// Leave a halt, forget the failure count and connect now.
    case restart
    /// Drop a healthy connection and connect again, e.g. because the topic set changed.
    case reconnect
    /// The stream reported `open`.
    case opened
    /// Any other sign of life: keepalive, message, poll request.
    case activity
    case failed(NtfyError)
    /// The server closed the connection cleanly.
    case finished
    /// The driver's timer for `wakeUp` fired.
    case timerFired
    case system(SystemEvent)
  }

  public enum Command: Sendable, Hashable {
    /// Start a connection attempt (replacing any live one).
    case connect
    /// Cancel the live connection, if any.
    case disconnect
  }

  public private(set) var status: ConnectionStatus = .stopped
  /// When the driver must call `.timerFired`: the end of a backoff, or the watchdog deadline.
  public private(set) var wakeUp: Date?

  private let timing: Timing
  private let jitter: @Sendable () -> Double
  private var running = false
  private var asleep = false
  private var online: Bool
  private var attempt = 0
  private var openedAt: Date?
  private var lastActivity: Date?
  private var largestGap: TimeInterval = 0

  /// - Parameter jitter: a value in 0...1; backoff delays are scaled into 50...100 % by it.
  public init(
    timing: Timing = Timing(), online: Bool = true,
    jitter: @escaping @Sendable () -> Double
  ) {
    self.timing = timing
    self.online = online
    self.jitter = jitter
  }

  public mutating func handle(_ input: Input, at now: Date) -> Command? {
    switch input {
    case .start, .stop, .restart, .reconnect:
      return handleLifecycle(input, at: now)
    case .opened, .activity, .failed, .finished, .timerFired:
      return handleConnection(input, at: now)
    case .system(let event):
      return handleSystem(event, at: now)
    }
  }
}

// MARK: - Inputs

extension ReconnectMachine {
  private var isLive: Bool {
    if case .halted = status { return false }
    return running
  }

  private var isConnectionActive: Bool { status == .connecting || status == .connected }

  private mutating func handleLifecycle(_ input: Input, at now: Date) -> Command? {
    switch input {
    case .start:
      guard !running else { return nil }
      running = true
      return settle(at: now)
    case .stop:
      running = false
      return park(.stopped, at: now)
    case .restart:
      running = true
      attempt = 0
      largestGap = 0
      status = .stopped
      return settle(at: now)
    default:
      guard status == .connected else { return nil }
      attempt = 0
      return settle(at: now)
    }
  }

  private mutating func handleSystem(_ event: SystemEvent, at now: Date) -> Command? {
    switch event {
    case .willSleep:
      asleep = true
      return isLive ? park(.paused, at: now) : nil
    case .didWake:
      asleep = false
      guard isLive else { return nil }
      attempt = 0
      return settle(at: now)
    case .screensDidSleep, .screenLocked, .screenUnlocked:
      return nil
    case .screensDidWake:
      return handleScreensDidWake(at: now)
    case .pathChanged(let isOnline):
      let wasOnline = online
      online = isOnline
      guard isLive, !asleep else { return nil }
      if !isOnline { return park(.offline, at: now) }
      guard !wasOnline else { return nil }
      attempt = 0
      return settle(at: now)
    }
  }

  /// Someone is at the Mac, so it is awake whatever the last sleep event said; a parked or
  /// waiting connection should not make them wait for its timer.
  private mutating func handleScreensDidWake(at now: Date) -> Command? {
    asleep = false
    guard isLive else { return nil }
    switch status {
    case .paused, .backingOff:
      attempt = 0
      return settle(at: now)
    default:
      return nil
    }
  }

  private mutating func handleConnection(_ input: Input, at now: Date) -> Command? {
    switch input {
    case .opened, .activity:
      noteLife(at: now)
      return nil
    case .failed(let error):
      return isConnectionActive ? fail(error, at: now) : nil
    case .finished:
      return isConnectionActive ? finish(at: now) : nil
    default:
      return fire(at: now)
    }
  }
}

// MARK: - Transitions

extension ReconnectMachine {
  /// Connects if nothing forbids it, otherwise parks in the state that explains why.
  private mutating func settle(at now: Date) -> Command? {
    guard running else { return park(.stopped, at: now) }
    if case .halted = status { return nil }
    if asleep { return park(.paused, at: now) }
    if !online { return park(.offline, at: now) }
    return beginConnecting(at: now)
  }

  private mutating func beginConnecting(at now: Date) -> Command {
    status = .connecting
    openedAt = nil
    lastActivity = nil
    wakeUp = now.addingTimeInterval(timing.connectTimeout)
    return .connect
  }

  /// Leaves the connection. `paused` and `offline` get a probe time (see the type's notes);
  /// every other state waits for an input or sets its own `wakeUp`.
  private mutating func park(_ parked: ConnectionStatus, at now: Date) -> Command {
    status = parked
    switch parked {
    case .paused, .offline: wakeUp = now.addingTimeInterval(timing.parkedProbe)
    default: wakeUp = nil
    }
    openedAt = nil
    lastActivity = nil
    return .disconnect
  }

  private mutating func noteLife(at now: Date) {
    switch status {
    case .connecting:
      status = .connected
      openedAt = now
    case .connected:
      largestGap = max(largestGap, now.timeIntervalSince(lastActivity ?? now))
    default:
      return
    }
    lastActivity = now
    let silence = min(max(timing.watchdogFloor, 2 * largestGap), timing.watchdogCap)
    wakeUp = now.addingTimeInterval(silence)
  }

  private mutating func fire(at now: Date) -> Command? {
    guard let due = wakeUp, now >= due else { return nil }
    switch status {
    case .backingOff: return settle(at: now)
    case .connecting, .connected: return fail(.serverUnreachable, at: now)
    case .paused:
      asleep = false
      attempt = 0
      return settle(at: now)
    case .offline:
      return beginConnecting(at: now)
    default: return nil
    }
  }

  private mutating func fail(_ error: NtfyError, at now: Date) -> Command {
    resetIfHealthy(at: now)
    if Self.isTerminal(error) { return park(.halted(error), at: now) }
    attempt += 1
    return retry(after: delay(for: error), at: now)
  }

  private mutating func finish(at now: Date) -> Command {
    guard wasHealthy(at: now) else { return fail(.serverUnreachable, at: now) }
    attempt = 0
    return retry(after: timing.cleanFinishDelay, at: now)
  }

  private mutating func retry(after delay: TimeInterval, at now: Date) -> Command {
    let until = now.addingTimeInterval(delay)
    _ = park(.backingOff(until: until, attempt: attempt), at: now)
    wakeUp = until
    return .disconnect
  }

  private func wasHealthy(at now: Date) -> Bool {
    guard let openedAt else { return false }
    return now.timeIntervalSince(openedAt) >= timing.healthyAfter
  }

  private mutating func resetIfHealthy(at now: Date) {
    if wasHealthy(at: now) { attempt = 0 }
  }
}

// MARK: - Policy

extension ReconnectMachine {
  /// Failures a retry cannot fix: the credentials, the URL or the topic names need changing.
  public static func isTerminal(_ error: NtfyError) -> Bool {
    switch error {
    case .unauthorized, .redirected, .invalidTopic, .insecureServer: return true
    default: return false
    }
  }

  private func delay(for error: NtfyError) -> TimeInterval {
    let doublings = Double(1 << min(max(attempt - 1, 0), 16))
    let base = min(timing.initialBackoff * doublings, timing.maxBackoff)
    let scale = 0.5 + 0.5 * min(max(jitter(), 0), 1)
    let jittered = base * scale
    guard case .rateLimited(let retryAfter) = error else { return jittered }
    let floor = max(timing.rateLimitFloor, TimeInterval(retryAfter ?? 0))
    return min(max(jittered, floor), timing.rateLimitCap)
  }
}
