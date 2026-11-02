import NtfyCore

public actor InMemoryCursorStore: CursorStore {
  private var cursor: String?
  private var saveFailure: NtfyError?
  public private(set) var saved: [String] = []

  public init(_ cursor: String? = nil) {
    self.cursor = cursor
  }

  public func load() -> String? { cursor }

  public func save(_ id: String) throws(NtfyError) {
    if let saveFailure { throw saveFailure }
    cursor = id
    saved.append(id)
  }

  /// Makes every following `save` throw `failure`, or work again with `nil`.
  public func setSaveFailure(_ failure: NtfyError?) {
    saveFailure = failure
  }
}
