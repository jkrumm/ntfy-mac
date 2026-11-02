import Foundation
import NtfyCore

/// Feeds the machine inputs at moments the test chooses.
struct Rig {
  var machine: ReconnectMachine
  var now = Date(timeIntervalSince1970: 1_700_000_000)

  init(online: Bool = true, jitter: Double = 1) {
    machine = ReconnectMachine(online: online, jitter: { jitter })
  }

  var status: ConnectionStatus { machine.status }

  @discardableResult
  mutating func send(_ input: ReconnectMachine.Input, after seconds: TimeInterval = 0)
    -> ReconnectMachine.Command?
  {
    now = now.addingTimeInterval(seconds)
    return machine.handle(input, at: now)
  }

  /// The delay of the backoff the machine is in.
  var delay: TimeInterval? {
    guard case .backingOff(let until, _) = status else { return nil }
    return until.timeIntervalSince(now)
  }

  var attempt: Int? {
    guard case .backingOff(_, let attempt) = status else { return nil }
    return attempt
  }

  /// Starts and opens a connection that then stays up for `uptime` seconds.
  mutating func connectAndStayUp(for uptime: TimeInterval) {
    send(.start)
    send(.opened, after: 1)
    send(.activity, after: uptime)
  }
}
