import OSLog

/// One subsystem, a fixed set of categories. Loggers are cheap value types; nothing is cached.
public enum Log {
  public static let subsystem = "com.jkrumm.ntfy-mac"

  public enum Category: String, Sendable, CaseIterable {
    case stream
    case delivery
    case store
    case ipc
    case cli
    case interface
    case meeting
  }

  public static func logger(_ category: Category) -> Logger {
    Logger(subsystem: subsystem, category: category.rawValue)
  }
}
