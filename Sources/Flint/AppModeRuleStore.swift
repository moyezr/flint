import Foundation
import SQLite3

struct AppModeRule: Equatable, Identifiable {
    let id: Int64
    let appBundleID: String?
    let urlPattern: String?
    let mode: CleanupMode
    let enabled: Bool
    let createdAt: Date
    let updatedAt: Date
}

private let APP_MODE_RULE_SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct NewAppModeRule: Equatable {
    let appBundleID: String?
    let urlPattern: String?
    let mode: CleanupMode
    let enabled: Bool

    init(
        appBundleID: String? = nil,
        urlPattern: String? = nil,
        mode: CleanupMode,
        enabled: Bool = true
    ) {
        self.appBundleID = appBundleID
        self.urlPattern = urlPattern
        self.mode = mode
        self.enabled = enabled
    }
}

struct AppModeRuleChanges: Equatable {
    var appBundleID: String??
    var urlPattern: String??
    var mode: CleanupMode?
    var enabled: Bool?

    init(
        appBundleID: String?? = nil,
        urlPattern: String?? = nil,
        mode: CleanupMode? = nil,
        enabled: Bool? = nil
    ) {
        self.appBundleID = appBundleID
        self.urlPattern = urlPattern
        self.mode = mode
        self.enabled = enabled
    }
}

struct AppModeRuleStore {
    enum AppModeRuleStoreError: LocalizedError, Equatable {
        case sqlite(message: String)
        case invalidMatcher
        case invalidDate(String)
        case notFound(Int64)

        var errorDescription: String? {
            switch self {
            case .sqlite(let message):
                return message
            case .invalidMatcher:
                return "An app mode rule must have an app bundle ID or URL pattern."
            case .invalidDate(let value):
                return "Invalid app mode rule timestamp: \(value)"
            case .notFound(let id):
                return "App mode rule not found: \(id)"
            }
        }
    }

    let databaseURL: URL

    private let fileManager: FileManager
    private let dateProvider: () -> Date

    init(
        databaseURL: URL = HistoryStore.defaultDatabaseURL(),
        fileManager: FileManager = .default,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    @discardableResult
    func create(_ rule: NewAppModeRule) throws -> AppModeRule {
        let sanitized = try sanitize(appBundleID: rule.appBundleID, urlPattern: rule.urlPattern)
        try migrate()
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let now = dateProvider()
        let statement = try prepare(
            """
            INSERT INTO app_mode_rules (
                app_bundle_id, url_pattern, mode, enabled, created_at, updated_at
            ) VALUES (?, ?, ?, ?, ?, ?);
            """,
            db: db
        )
        defer { sqlite3_finalize(statement) }

        bind(text: sanitized.appBundleID, to: 1, statement: statement)
        bind(text: sanitized.urlPattern, to: 2, statement: statement)
        bind(text: rule.mode.rawValue, to: 3, statement: statement)
        sqlite3_bind_int(statement, 4, rule.enabled ? 1 : 0)
        bind(text: Self.formatter.string(from: now), to: 5, statement: statement)
        bind(text: Self.formatter.string(from: now), to: 6, statement: statement)

        try stepDone(statement, db: db)
        return AppModeRule(
            id: sqlite3_last_insert_rowid(db),
            appBundleID: sanitized.appBundleID,
            urlPattern: sanitized.urlPattern,
            mode: rule.mode,
            enabled: rule.enabled,
            createdAt: now,
            updatedAt: now
        )
    }

    func list(includeDisabled: Bool = true) throws -> [AppModeRule] {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return []
        }
        try migrate()
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let whereClause = includeDisabled ? "" : "WHERE enabled = 1"
        let statement = try prepare(
            """
            SELECT id, app_bundle_id, url_pattern, mode, enabled, created_at, updated_at
            FROM app_mode_rules
            \(whereClause)
            ORDER BY created_at ASC, id ASC;
            """,
            db: db
        )
        defer { sqlite3_finalize(statement) }

        var rules: [AppModeRule] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let rule = try readRule(from: statement) {
                rules.append(rule)
            }
        }
        return rules
    }

    func rule(id: Int64) throws -> AppModeRule? {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return nil
        }
        try migrate()
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let statement = try prepare(
            """
            SELECT id, app_bundle_id, url_pattern, mode, enabled, created_at, updated_at
            FROM app_mode_rules
            WHERE id = ?;
            """,
            db: db
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }
        return try readRule(from: statement)
    }

    @discardableResult
    func update(id: Int64, changes: AppModeRuleChanges) throws -> AppModeRule {
        guard let existing = try rule(id: id) else {
            throw AppModeRuleStoreError.notFound(id)
        }

        let sanitized = try sanitize(
            appBundleID: changedValue(changes.appBundleID, fallback: existing.appBundleID),
            urlPattern: changedValue(changes.urlPattern, fallback: existing.urlPattern)
        )
        let mode = changes.mode ?? existing.mode
        let enabled = changes.enabled ?? existing.enabled
        let updatedAt = dateProvider()

        try migrate()
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let statement = try prepare(
            """
            UPDATE app_mode_rules
            SET app_bundle_id = ?, url_pattern = ?, mode = ?, enabled = ?, updated_at = ?
            WHERE id = ?;
            """,
            db: db
        )
        defer { sqlite3_finalize(statement) }

        bind(text: sanitized.appBundleID, to: 1, statement: statement)
        bind(text: sanitized.urlPattern, to: 2, statement: statement)
        bind(text: mode.rawValue, to: 3, statement: statement)
        sqlite3_bind_int(statement, 4, enabled ? 1 : 0)
        bind(text: Self.formatter.string(from: updatedAt), to: 5, statement: statement)
        sqlite3_bind_int64(statement, 6, id)

        try stepDone(statement, db: db)
        return AppModeRule(
            id: existing.id,
            appBundleID: sanitized.appBundleID,
            urlPattern: sanitized.urlPattern,
            mode: mode,
            enabled: enabled,
            createdAt: existing.createdAt,
            updatedAt: updatedAt
        )
    }

    @discardableResult
    func setEnabled(_ enabled: Bool, id: Int64) throws -> AppModeRule {
        try update(id: id, changes: AppModeRuleChanges(enabled: enabled))
    }

    func delete(id: Int64) throws {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return
        }
        try migrate()
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let statement = try prepare("DELETE FROM app_mode_rules WHERE id = ?;", db: db)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, id)
        try stepDone(statement, db: db)
    }

    func deleteAll() throws {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return
        }
        try migrate()
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try execute("DELETE FROM app_mode_rules;", db: db)
    }

    func deleteDatabaseFiles() throws {
        try HistoryStore(databaseURL: databaseURL, fileManager: fileManager).deleteDatabaseFiles()
    }

    func migrate() throws {
        try HistoryStore(databaseURL: databaseURL, fileManager: fileManager).migrate()
    }

    private func sanitize(appBundleID: String?, urlPattern: String?) throws -> (appBundleID: String?, urlPattern: String?) {
        let sanitizedAppBundleID = sanitized(appBundleID)
        let sanitizedURLPattern = sanitized(urlPattern)
        guard sanitizedAppBundleID != nil || sanitizedURLPattern != nil else {
            throw AppModeRuleStoreError.invalidMatcher
        }
        return (sanitizedAppBundleID, sanitizedURLPattern)
    }

    private func sanitized(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    private func changedValue(_ changedValue: String??, fallback: String?) -> String? {
        guard let changedValue else {
            return fallback
        }
        return changedValue
    }

    private func openDatabase() throws -> OpaquePointer? {
        var db: OpaquePointer?
        guard sqlite3_open(databaseURL.path, &db) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open history database."
            if let db {
                sqlite3_close(db)
            }
            throw AppModeRuleStoreError.sqlite(message: message)
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
        sqlite3_bind_text(statement, index, text, -1, APP_MODE_RULE_SQLITE_TRANSIENT)
    }

    private func readRule(from statement: OpaquePointer?) throws -> AppModeRule? {
        guard let modeRawValue = string(at: 3, statement: statement),
              let mode = CleanupMode(rawValue: modeRawValue) else {
            return nil
        }

        let createdAtString = string(at: 5, statement: statement) ?? ""
        let updatedAtString = string(at: 6, statement: statement) ?? ""
        guard let createdAt = Self.formatter.date(from: createdAtString) else {
            throw AppModeRuleStoreError.invalidDate(createdAtString)
        }
        guard let updatedAt = Self.formatter.date(from: updatedAtString) else {
            throw AppModeRuleStoreError.invalidDate(updatedAtString)
        }

        let appBundleID = sanitized(string(at: 1, statement: statement))
        let urlPattern = sanitized(string(at: 2, statement: statement))
        guard appBundleID != nil || urlPattern != nil else {
            return nil
        }

        return AppModeRule(
            id: sqlite3_column_int64(statement, 0),
            appBundleID: appBundleID,
            urlPattern: urlPattern,
            mode: mode,
            enabled: sqlite3_column_int(statement, 4) != 0,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private func string(at column: Int32, statement: OpaquePointer?) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: value)
    }

    private func sqliteError(_ db: OpaquePointer?) -> AppModeRuleStoreError {
        AppModeRuleStoreError.sqlite(message: String(cString: sqlite3_errmsg(db)))
    }

    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
