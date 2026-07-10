import Foundation
import SQLite3

struct HistoryEntry: Equatable, Identifiable {
    let id: Int64
    let createdAt: Date
    let activeAppName: String?
    let activeAppBundleID: String?
    let mode: String
    let rawTranscript: String
    let finalText: String
    let durationMS: Int
    let modelName: String
    let language: String
}

struct NewHistoryEntry: Equatable {
    let createdAt: Date
    let activeAppName: String?
    let activeAppBundleID: String?
    let mode: String
    let rawTranscript: String
    let finalText: String
    let durationMS: Int
    let modelName: String
    let language: String
}

struct DictationHistoryRecorder {
    enum RecorderError: LocalizedError, Equatable {
        case historyUnavailable

        var errorDescription: String? {
            switch self {
            case .historyUnavailable:
                return "History storage is unavailable."
            }
        }
    }

    var settingsProvider: () -> AppSettings
    var historyStore: HistoryStore?
    var dateProvider: () -> Date = Date.init

    @discardableResult
    func record(
        rawTranscript: String,
        finalText: String,
        durationMS: Int,
        activeApp: ActiveAppInfo?,
        mode: CleanupMode,
        modelName: String,
        language: String? = nil
    ) throws -> HistoryEntry? {
        let settings = settingsProvider()
        guard settings.storeHistory else {
            return nil
        }
        guard let historyStore else {
            throw RecorderError.historyUnavailable
        }

        return try historyStore.insert(NewHistoryEntry(
            createdAt: dateProvider(),
            activeAppName: activeApp?.name,
            activeAppBundleID: activeApp?.bundleIdentifier,
            mode: mode.rawValue,
            rawTranscript: rawTranscript,
            finalText: finalText,
            durationMS: durationMS,
            modelName: modelName,
            language: language ?? settings.language
        ))
    }
}

struct HistoryStore {
    enum HistoryStoreError: LocalizedError, Equatable {
        case sqlite(message: String)
        case invalidDate(String)

        var errorDescription: String? {
            switch self {
            case .sqlite(let message):
                return message
            case .invalidDate(let value):
                return "Invalid history timestamp: \(value)"
            }
        }
    }

    let databaseURL: URL

    private let fileManager: FileManager
    private static let schemaVersion: Int32 = 2

    init(
        databaseURL: URL = HistoryStore.defaultDatabaseURL(),
        fileManager: FileManager = .default
    ) throws {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
    }

    static func defaultDatabaseURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("Flint", isDirectory: true)
            .appendingPathComponent("History.sqlite")
    }

    func insert(_ entry: NewHistoryEntry) throws -> HistoryEntry {
        try migrate()
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let sql = """
        INSERT INTO dictation_history (
            created_at, active_app_name, active_app_bundle_id, mode,
            raw_transcript, final_text, duration_ms, model_name, language
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        let statement = try prepare(sql, db: db)
        defer { sqlite3_finalize(statement) }

        bind(text: Self.formatter.string(from: entry.createdAt), to: 1, statement: statement)
        bind(text: entry.activeAppName, to: 2, statement: statement)
        bind(text: entry.activeAppBundleID, to: 3, statement: statement)
        bind(text: entry.mode, to: 4, statement: statement)
        bind(text: entry.rawTranscript, to: 5, statement: statement)
        bind(text: entry.finalText, to: 6, statement: statement)
        sqlite3_bind_int(statement, 7, Int32(entry.durationMS))
        bind(text: entry.modelName, to: 8, statement: statement)
        bind(text: entry.language, to: 9, statement: statement)

        try stepDone(statement, db: db)
        return HistoryEntry(
            id: sqlite3_last_insert_rowid(db),
            createdAt: entry.createdAt,
            activeAppName: entry.activeAppName,
            activeAppBundleID: entry.activeAppBundleID,
            mode: entry.mode,
            rawTranscript: entry.rawTranscript,
            finalText: entry.finalText,
            durationMS: entry.durationMS,
            modelName: entry.modelName,
            language: entry.language
        )
    }

    func list(limit: Int = 100) throws -> [HistoryEntry] {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return []
        }
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let statement = try prepare(
            """
            SELECT id, created_at, active_app_name, active_app_bundle_id, mode,
                   raw_transcript, final_text, duration_ms, model_name, language
            FROM dictation_history
            ORDER BY created_at DESC, id DESC
            LIMIT ?;
            """,
            db: db
        )
        defer { sqlite3_finalize(statement) }
        let boundedLimit = min(max(0, limit), Int(Int32.max))
        sqlite3_bind_int(statement, 1, Int32(boundedLimit))

        var entries: [HistoryEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            entries.append(try readEntry(from: statement))
        }
        return entries
    }

    func count() throws -> Int {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return 0
        }
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let statement = try prepare("SELECT COUNT(*) FROM dictation_history;", db: db)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw sqliteError(db)
        }
        return Int(sqlite3_column_int(statement, 0))
    }

    func delete(id: Int64) throws {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return
        }
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let statement = try prepare("DELETE FROM dictation_history WHERE id = ?;", db: db)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        try stepDone(statement, db: db)
    }

    func deleteAll() throws {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return
        }
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try execute("DELETE FROM dictation_history;", db: db)
    }

    func deleteDatabaseFiles() throws {
        for url in databaseFileURLs() where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func export(to url: URL) throws {
        let entries = try list(limit: Int.max)
        let payload = entries.map(ExportedHistoryEntry.init(entry:))
        let data = try JSONEncoder.flintHistory.encode(payload)
        try data.write(to: url, options: .atomic)
    }

    func migrate() throws {
        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        try execute("PRAGMA journal_mode = WAL;", db: db)
        try execute("PRAGMA foreign_keys = ON;", db: db)
        try execute(
            """
            CREATE TABLE IF NOT EXISTS dictation_history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                created_at TEXT NOT NULL,
                active_app_name TEXT,
                active_app_bundle_id TEXT,
                mode TEXT NOT NULL,
                raw_transcript TEXT NOT NULL,
                final_text TEXT NOT NULL,
                duration_ms INTEGER NOT NULL,
                model_name TEXT NOT NULL,
                language TEXT NOT NULL
            );
            """,
            db: db
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS idx_dictation_history_created_at
            ON dictation_history(created_at DESC);
            """,
            db: db
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS app_mode_rules (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                app_bundle_id TEXT,
                url_pattern TEXT,
                mode TEXT NOT NULL,
                enabled INTEGER NOT NULL DEFAULT 1,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                CHECK (
                    (app_bundle_id IS NOT NULL AND length(trim(app_bundle_id)) > 0)
                    OR (url_pattern IS NOT NULL AND length(trim(url_pattern)) > 0)
                )
            );
            """,
            db: db
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS idx_app_mode_rules_enabled_bundle_id
            ON app_mode_rules(app_bundle_id, created_at, id)
            WHERE enabled = 1 AND app_bundle_id IS NOT NULL;
            """,
            db: db
        )
        try execute("PRAGMA user_version = \(Self.schemaVersion);", db: db)
    }

    private func openDatabase() throws -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open history database."
            if let db {
                sqlite3_close(db)
            }
            throw HistoryStoreError.sqlite(message: message)
        }
        return db
    }

    private func execute(_ sql: String, db: OpaquePointer?) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw sqliteError(db)
        }
    }

    private func prepare(_ sql: String, db: OpaquePointer?) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(db)
        }
        return statement
    }

    private func stepDone(_ statement: OpaquePointer?, db: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw sqliteError(db)
        }
    }

    private func bind(text: String?, to index: Int32, statement: OpaquePointer?) {
        guard let text else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, text, -1, SQLITE_TRANSIENT)
    }

    private func readEntry(from statement: OpaquePointer?) throws -> HistoryEntry {
        let createdAtString = string(at: 1, statement: statement) ?? ""
        guard let createdAt = Self.formatter.date(from: createdAtString) else {
            throw HistoryStoreError.invalidDate(createdAtString)
        }

        return HistoryEntry(
            id: sqlite3_column_int64(statement, 0),
            createdAt: createdAt,
            activeAppName: string(at: 2, statement: statement),
            activeAppBundleID: string(at: 3, statement: statement),
            mode: string(at: 4, statement: statement) ?? "",
            rawTranscript: string(at: 5, statement: statement) ?? "",
            finalText: string(at: 6, statement: statement) ?? "",
            durationMS: Int(sqlite3_column_int(statement, 7)),
            modelName: string(at: 8, statement: statement) ?? "",
            language: string(at: 9, statement: statement) ?? ""
        )
    }

    private func string(at column: Int32, statement: OpaquePointer?) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: value)
    }

    private func sqliteError(_ db: OpaquePointer?) -> HistoryStoreError {
        HistoryStoreError.sqlite(message: String(cString: sqlite3_errmsg(db)))
    }

    private func databaseFileURLs() -> [URL] {
        [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ]
    }

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private struct ExportedHistoryEntry: Encodable {
    let id: Int64
    let createdAt: String
    let activeAppName: String?
    let activeAppBundleID: String?
    let mode: String
    let rawTranscript: String
    let finalText: String
    let durationMS: Int
    let modelName: String
    let language: String

    init(entry: HistoryEntry) {
        id = entry.id
        createdAt = HistoryStoreExportDateFormatter.string(from: entry.createdAt)
        activeAppName = entry.activeAppName
        activeAppBundleID = entry.activeAppBundleID
        mode = entry.mode
        rawTranscript = entry.rawTranscript
        finalText = entry.finalText
        durationMS = entry.durationMS
        modelName = entry.modelName
        language = entry.language
    }
}

private enum HistoryStoreExportDateFormatter {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }
}

private extension JSONEncoder {
    static var flintHistory: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }
}
