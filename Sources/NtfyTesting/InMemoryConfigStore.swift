import NtfyCore

public actor InMemoryConfigStore: ConfigStore {
  private var config: Config

  public init(_ config: Config = Config()) {
    self.config = config
  }

  public func load() -> Config { config }
  public func save(_ config: Config) { self.config = config }
  public func update(_ change: @Sendable (inout Config) -> Void) { change(&config) }
}
