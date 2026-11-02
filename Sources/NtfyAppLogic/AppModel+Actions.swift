import Foundation
import NtfyCore

/// What the menu and the windows can do. Each action refreshes afterwards, so the model is right
/// without waiting for the history signal.
extension AppModel {
  /// Acknowledges the message and withdraws its notification.
  public func acknowledge(_ row: MessageRow) async {
    await handles?.delivery.acknowledge(topic: row.topic, id: row.key.id)
    await refresh()
  }

  public func acknowledgeAll() async {
    do throws(NtfyError) {
      _ = try await handles?.messages.acknowledgeAll(topic: nil)
    } catch {
      log("acknowledge all failed: \(error)")
    }
    await refresh()
  }

  public func markRead(_ row: MessageRow) async {
    do throws(NtfyError) {
      try await handles?.inbox.markRead(topic: row.topic, id: row.key.id)
    } catch {
      log("mark read failed: \(error)")
    }
    await refresh()
  }

  /// Holds notifications back until the choice's end. Messages still arrive and are stored.
  public func pause(_ choice: PauseChoice) async {
    let until = choice.end(from: clock.now(), calendar: calendar)
    await store(pausedUntil: until)
  }

  /// Ends a pause and shows what was held back.
  public func resume() async {
    await store(pausedUntil: nil)
    await handles?.delivery.reconcile()
  }

  /// Leaves a halt or a backoff and connects now; nothing without a server.
  public func reconnect() async {
    await handles?.supervisor?.restart()
  }

  private func store(pausedUntil until: Date?) async {
    do throws(NtfyError) {
      try await config.update { $0.pausedUntil = until }
    } catch {
      log("pause not stored: \(error)")
    }
    await refresh()
  }
}
