import NtfyCore
import Synchronization

/// An instance lock that lives in memory. Every `acquire` on one value contends for the same
/// lock, like two processes on one lock file.
public final class InMemoryInstanceLock: InstanceLocking {
  private final class Lease: InstanceLease {
    private let onRelease: @Sendable () -> Void
    init(_ release: @escaping @Sendable () -> Void) { onRelease = release }
    func release() { onRelease() }
  }

  private struct State {
    var holder = 0
    var next = 1
    var failure: NtfyError?
  }

  /// A class, so a lease can keep the state it must clear (a `Mutex` cannot be captured).
  private final class Box: Sendable {
    let state = Mutex(State())
  }

  private let box = Box()

  /// - Parameter failure: `acquire` throws this instead of answering.
  public init(failure: NtfyError? = nil) {
    box.state.withLock { $0.failure = failure }
  }

  public var isHeld: Bool { box.state.withLock { $0.holder != 0 } }

  public func acquire() throws(NtfyError) -> (any InstanceLease)? {
    let outcome: Result<Int?, NtfyError> = box.state.withLock { state in
      if let failure = state.failure { return .failure(failure) }
      guard state.holder == 0 else { return .success(nil) }
      let id = state.next
      state.next += 1
      state.holder = id
      return .success(id)
    }
    switch outcome {
    case .failure(let error): throw error
    case .success(nil): return nil
    case .success(let id?):
      return Lease { [box] in box.state.withLock { if $0.holder == id { $0.holder = 0 } } }
    }
  }
}
