import GRDB

/// The database schema, one migration per change. Each migration is its own transaction.
enum HistorySchema {
  static var migrator: DatabaseMigrator {
    var migrator = DatabaseMigrator()
    migrator.registerMigration("v1-messages") { database in
      try database.execute(
        sql: """
          CREATE TABLE message (
            pk INTEGER PRIMARY KEY AUTOINCREMENT,
            server TEXT NOT NULL,
            topic TEXT NOT NULL,
            id TEXT NOT NULL,
            sequence_id TEXT NOT NULL,
            time DATETIME NOT NULL,
            title TEXT,
            body TEXT NOT NULL,
            priority INTEGER NOT NULL,
            tags TEXT NOT NULL,
            payload BLOB NOT NULL,
            read_at DATETIME,
            acked_at DATETIME,
            notified_at DATETIME,
            remind_at DATETIME,
            withdrawn_at DATETIME,
            created_at DATETIME NOT NULL
          );
          CREATE UNIQUE INDEX message_key ON message (server, topic, id);
          CREATE INDEX message_topic_time ON message (server, topic, time);
          CREATE INDEX message_sequence ON message (server, topic, sequence_id);
          CREATE INDEX message_unread ON message (server, topic, time) WHERE read_at IS NULL;
          CREATE INDEX message_unacked ON message (server, priority) WHERE acked_at IS NULL;
          CREATE INDEX message_unnotified ON message (server, time) WHERE notified_at IS NULL;
          CREATE INDEX message_reminder ON message (server, remind_at) WHERE remind_at IS NOT NULL;
          """)
      try database.create(virtualTable: "message_ft", using: FTS5()) { table in
        table.synchronize(withTable: "message")
        table.column("title")
        table.column("body")
      }
    }
    return migrator
  }
}
