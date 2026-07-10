import SQLite3
import XCTest
@testable import Flint

final class AppModeRuleStoreTests: XCTestCase {
    private var tempRoot: URL!
    private var databaseURL: URL!
    private var dates: [Date]!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-app-mode-rule-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        databaseURL = tempRoot.appendingPathComponent("History.sqlite")
        dates = [
            Date(timeIntervalSince1970: 100),
            Date(timeIntervalSince1970: 200),
            Date(timeIntervalSince1970: 300),
            Date(timeIntervalSince1970: 400)
        ]
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        databaseURL = nil
        dates = nil
        try super.tearDownWithError()
    }

    func testInitAndReadOnlyListDoNotCreateDatabase() throws {
        let store = makeStore()

        XCTAssertEqual(try store.list(), [])
        XCTAssertNil(try store.rule(id: 42))
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testCreateListUpdateEnableAndDeleteRules() throws {
        let store = makeStore()
        let first = try store.create(NewAppModeRule(
            appBundleID: "  com.apple.mail  ",
            urlPattern: "  https://mail.example.com  ",
            mode: .email
        ))
        let second = try store.create(NewAppModeRule(
            appBundleID: "com.apple.Notes",
            mode: .message,
            enabled: false
        ))

        XCTAssertEqual(first.appBundleID, "com.apple.mail")
        XCTAssertEqual(first.urlPattern, "https://mail.example.com")
        XCTAssertEqual(first.mode, .email)
        XCTAssertTrue(first.enabled)
        XCTAssertEqual(first.createdAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(first.updatedAt, Date(timeIntervalSince1970: 100))
        XCTAssertEqual(try store.list().map(\.id), [first.id, second.id])
        XCTAssertEqual(try store.list(includeDisabled: false).map(\.id), [first.id])

        let updated = try store.update(
            id: first.id,
            changes: AppModeRuleChanges(
                appBundleID: .some("com.apple.Safari"),
                urlPattern: .some(nil),
                mode: .prompt,
                enabled: false
            )
        )

        XCTAssertEqual(updated.id, first.id)
        XCTAssertEqual(updated.appBundleID, "com.apple.Safari")
        XCTAssertNil(updated.urlPattern)
        XCTAssertEqual(updated.mode, .prompt)
        XCTAssertFalse(updated.enabled)
        XCTAssertEqual(updated.createdAt, first.createdAt)
        XCTAssertEqual(updated.updatedAt, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(try store.rule(id: first.id), updated)

        let enabled = try store.setEnabled(true, id: first.id)
        XCTAssertTrue(enabled.enabled)
        XCTAssertEqual(enabled.updatedAt, Date(timeIntervalSince1970: 400))

        try store.delete(id: second.id)
        XCTAssertEqual(try store.list().map(\.id), [first.id])

        try store.deleteAll()
        XCTAssertEqual(try store.list(), [])
    }

    func testCreateAndUpdateRequireAtLeastOneNonEmptyMatcher() throws {
        let store = makeStore()

        XCTAssertThrowsError(try store.create(NewAppModeRule(
            appBundleID: "  ",
            urlPattern: "\n",
            mode: .clean
        ))) { error in
            XCTAssertEqual(error as? AppModeRuleStore.AppModeRuleStoreError, .invalidMatcher)
        }

        let rule = try store.create(NewAppModeRule(appBundleID: "com.apple.mail", mode: .email))
        XCTAssertThrowsError(try store.update(
            id: rule.id,
            changes: AppModeRuleChanges(appBundleID: .some(nil), urlPattern: .some(" "))
        )) { error in
            XCTAssertEqual(error as? AppModeRuleStore.AppModeRuleStoreError, .invalidMatcher)
        }
    }

    func testRulesWorkWhenLocalHistoryIsDisabled() throws {
        var settings = AppSettings.default
        settings.storeHistory = false
        let ruleStore = makeStore()
        let recorder = DictationHistoryRecorder(
            settingsProvider: { settings },
            historyStore: try HistoryStore(databaseURL: databaseURL)
        )

        _ = try ruleStore.create(NewAppModeRule(appBundleID: "com.apple.mail", mode: .email))
        _ = try recorder.record(
            rawTranscript: "raw",
            finalText: "final",
            durationMS: 1,
            activeApp: nil,
            mode: .clean,
            modelName: "base"
        )

        XCTAssertEqual(try ruleStore.list().map(\.mode), [.email])
        XCTAssertEqual(try HistoryStore(databaseURL: databaseURL).count(), 0)
    }

    func testV1MigrationPreservesHistoryAndAddsRuleSchema() throws {
        try createV1HistoryDatabase()
        let historyStore = try HistoryStore(databaseURL: databaseURL)

        try historyStore.migrate()

        XCTAssertEqual(try historyStore.count(), 1)
        XCTAssertEqual(try historyStore.list().first?.finalText, "Final words.")
        let rule = try makeStore().create(NewAppModeRule(appBundleID: "com.apple.mail", mode: .email))
        XCTAssertEqual(try makeStore().list(), [rule])
        XCTAssertEqual(try userVersion(), 2)
    }

    func testCorruptStoredModesAreIgnoredDuringListAndResolve() throws {
        let store = makeStore()
        let valid = try store.create(NewAppModeRule(appBundleID: "com.apple.mail", mode: .email))
        try insertRawRule(appBundleID: "com.apple.mail", mode: "not-a-mode", createdAt: 50)

        XCTAssertEqual(try store.list(), [valid])

        let resolved = AppModeResolver().resolve(
            context: AppModeResolutionContext(
                appAwareModesEnabled: true,
                manualMode: .clean,
                activeAppBundleID: "com.apple.mail"
            ),
            rules: try store.list()
        )
        XCTAssertEqual(resolved, .email)
    }

    private func makeStore() -> AppModeRuleStore {
        AppModeRuleStore(databaseURL: databaseURL, dateProvider: { self.dates.removeFirst() })
    }

    private func createV1HistoryDatabase() throws {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        try execute(
            """
            CREATE TABLE dictation_history (
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
            INSERT INTO dictation_history (
                created_at, active_app_name, active_app_bundle_id, mode,
                raw_transcript, final_text, duration_ms, model_name, language
            ) VALUES (
                '1970-01-01T00:00:01.000Z', 'Notes', 'com.apple.Notes', 'clean',
                'raw words', 'Final words.', 123, 'base', 'auto'
            );
            """,
            db: db
        )
        try execute("PRAGMA user_version = 1;", db: db)
    }

    private func insertRawRule(appBundleID: String, mode: String, createdAt: TimeInterval) throws {
        try makeStore().migrate()
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let date = ISO8601DateFormatter.flintTestFormatter.string(from: Date(timeIntervalSince1970: createdAt))
        try execute(
            """
            INSERT INTO app_mode_rules (
                app_bundle_id, url_pattern, mode, enabled, created_at, updated_at
            ) VALUES (
                '\(appBundleID)', NULL, '\(mode)', 1, '\(date)', '\(date)'
            );
            """,
            db: db
        )
    }

    private func userVersion() throws -> Int {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(db, "PRAGMA user_version;", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        return Int(sqlite3_column_int(statement, 0))
    }

    private func execute(_ sql: String, db: OpaquePointer?) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "SQLite error"
            sqlite3_free(errorMessage)
            XCTFail(message)
            return
        }
    }
}

private extension ISO8601DateFormatter {
    static var flintTestFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }
}
