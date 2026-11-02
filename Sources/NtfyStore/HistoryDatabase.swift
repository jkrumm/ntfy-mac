import Foundation
import GRDB
import NtfyCore
import SQLite3

/// Opens the history database: the app as the single writer, the CLI as a read-only reader.
enum HistoryDatabase {
  private static let directoryMode = 0o700
  private static let fileMode = 0o600

  /// Creates the directory and file with private modes before SQLite sees them, since SQLite
  /// gives `-wal` and `-shm` the mode of the database file. Migrates to the current schema.
  static func openWriter(at url: URL) throws(NtfyError) -> DatabasePool {
    do {
      try prepareFiles(at: url)
      var configuration = Configuration()
      configuration.busyMode = .timeout(5)
      configuration.prepareDatabase(keepWALFile)
      let pool = try DatabasePool(path: url.path, configuration: configuration)
      try HistorySchema.migrator.migrate(pool)
      return pool
    } catch {
      throw HistoryError.map(error)
    }
  }

  /// Never migrates; fails with a typed error when the app has not created or has outgrown it.
  static func openReader(at url: URL) throws(NtfyError) -> DatabasePool {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw .storage("history database does not exist yet")
    }
    do {
      var configuration = Configuration()
      configuration.readonly = true
      let pool = try DatabasePool(path: url.path, configuration: configuration)
      try verifySchema(of: pool)
      return pool
    } catch {
      throw HistoryError.map(error)
    }
  }

  private static func verifySchema(of pool: DatabasePool) throws {
    let migrator = HistorySchema.migrator
    let state = try pool.read { database in
      (try migrator.hasCompletedMigrations(database), try migrator.hasBeenSuperseded(database))
    }
    if state.1 { throw NtfyError.storage("history database was written by a newer version") }
    if !state.0 { throw NtfyError.storage("history database is not initialised") }
  }

  private static func prepareFiles(at url: URL) throws {
    let manager = FileManager.default
    let directory = url.deletingLastPathComponent()
    try manager.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.posixPermissions: directoryMode])
    try manager.setAttributes([.posixPermissions: directoryMode], ofItemAtPath: directory.path)
    if !manager.fileExists(atPath: url.path) {
      manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: fileMode])
    }
    try manager.setAttributes([.posixPermissions: fileMode], ofItemAtPath: url.path)
  }

  /// Keeps `-wal` and `-shm` on disk after the last connection closes, so a read-only process
  /// can still open the database.
  private static func keepWALFile(_ database: Database) throws {
    var flag: CInt = 1
    let code = sqlite3_file_control(database.sqliteConnection, nil, SQLITE_FCNTL_PERSIST_WAL, &flag)
    guard code == SQLITE_OK else { throw NtfyError.storage("cannot persist the WAL file") }
  }
}

/// Turns anything a database call throws into the port's error type.
enum HistoryError {
  static func map(_ error: any Error) -> NtfyError {
    if let error = error as? NtfyError { return error }
    if let error = error as? DatabaseError {
      return .storage(
        "history database error \(error.extendedResultCode.rawValue): \(error.message ?? "unknown")"
      )
    }
    return .storage("history database: \(type(of: error))")
  }
}
