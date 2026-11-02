import Foundation

/// Turns SIGINT and SIGTERM into a quiet end of a long-running command.
enum Interrupt {
  static let runUntilInterrupted: InterruptibleRunner = { body in
    let task = Task { try await body() }
    let signals = [SIGINT, SIGTERM]
    for number in signals { signal(number, SIG_IGN) }
    let sources = signals.map { number in
      let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
      source.setEventHandler { task.cancel() }
      source.resume()
      return source
    }
    defer {
      for source in sources { source.cancel() }
      for number in signals { signal(number, SIG_DFL) }
    }
    do {
      try await task.value
    } catch {
      // A cancelled read or sleep is the interrupt arriving, whatever error it surfaces as.
      guard task.isCancelled else { throw error }
    }
  }
}
