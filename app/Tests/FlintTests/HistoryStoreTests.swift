import XCTest
@testable import Flint

final class HistoryStoreTests: XCTestCase {
    private var tempRoot: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-history-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        databaseURL = tempRoot.appendingPathComponent("History.sqlite")
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        databaseURL = nil
        try super.tearDownWithError()
    }

    func testInitAndReadOnlyCallsDoNotCreateDatabase() throws {
        let store = try HistoryStore(databaseURL: databaseURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertEqual(try store.count(), 0)
        XCTAssertEqual(try store.list(), [])
        try store.deleteAll()
        try store.delete(id: 123)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testMigrateCreatesSchemaIdempotently() throws {
        let store = try HistoryStore(databaseURL: databaseURL)
        try store.migrate()
        try store.migrate()

        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertEqual(try HistoryStore(databaseURL: databaseURL).count(), 0)
    }

    func testInsertListDeleteOneAndDeleteAll() throws {
        let store = try HistoryStore(databaseURL: databaseURL)
        let first = try store.insert(makeEntry(
            createdAt: Date(timeIntervalSince1970: 100),
            finalText: "First final"
        ))
        let second = try store.insert(makeEntry(
            createdAt: Date(timeIntervalSince1970: 200),
            finalText: "Second final"
        ))

        XCTAssertEqual(try store.count(), 2)
        XCTAssertEqual(try store.list().map(\.id), [second.id, first.id])
        XCTAssertEqual(try store.list(limit: 1).map(\.finalText), ["Second final"])

        try store.delete(id: second.id)
        XCTAssertEqual(try store.list().map(\.id), [first.id])

        try store.deleteAll()
        XCTAssertEqual(try store.count(), 0)
    }

    func testExportWritesJsonWithoutAudioPaths() throws {
        let store = try HistoryStore(databaseURL: databaseURL)
        _ = try store.insert(makeEntry(rawTranscript: "raw words", finalText: "Final words."))
        let exportURL = tempRoot.appendingPathComponent("export.json")

        try store.export(to: exportURL)

        let json = try String(contentsOf: exportURL)
        XCTAssertTrue(json.contains(#""raw_transcript" : "raw words""#))
        XCTAssertTrue(json.contains(#""final_text" : "Final words.""#))
        XCTAssertFalse(json.contains("audio"))
        XCTAssertFalse(json.contains("path"))
        XCTAssertFalse(json.contains("blob"))
    }

    func testDeleteDatabaseFilesRemovesHistoryDatabaseArtifacts() throws {
        let store = try HistoryStore(databaseURL: databaseURL)
        _ = try store.insert(makeEntry())
        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: databaseURL.path + "-shm")
        FileManager.default.createFile(atPath: walURL.path, contents: Data([1]))
        FileManager.default.createFile(atPath: shmURL.path, contents: Data([2]))

        try store.deleteDatabaseFiles()

        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: walURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shmURL.path))
        let reloadedStore = try HistoryStore(databaseURL: databaseURL)
        XCTAssertEqual(try reloadedStore.count(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testRecorderDoesNotCreateDatabaseWhenHistoryIsDisabled() throws {
        var settings = AppSettings.default
        settings.storeHistory = false
        let store = try HistoryStore(databaseURL: databaseURL)
        let recorder = DictationHistoryRecorder(
            settingsProvider: { settings },
            historyStore: store,
            dateProvider: { Date(timeIntervalSince1970: 300) }
        )

        let entry = try recorder.record(
            rawTranscript: "raw",
            finalText: "final",
            durationMS: 42,
            activeApp: ActiveAppInfo(name: "Mail", bundleIdentifier: "com.apple.mail"),
            mode: .email,
            modelName: "base",
            language: "en"
        )

        XCTAssertNil(entry)
        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
    }

    func testRecorderWritesCapturedMetadataWhenHistoryIsEnabled() throws {
        var settings = AppSettings.default
        settings.storeHistory = true
        settings.language = "auto"
        let store = try HistoryStore(databaseURL: databaseURL)
        let recorder = DictationHistoryRecorder(
            settingsProvider: { settings },
            historyStore: store,
            dateProvider: { Date(timeIntervalSince1970: 300) }
        )

        let entry = try XCTUnwrap(try recorder.record(
            rawTranscript: "raw",
            finalText: "final",
            durationMS: 42,
            activeApp: ActiveAppInfo(name: "Mail", bundleIdentifier: "com.apple.mail"),
            mode: .email,
            modelName: "small",
            language: "en"
        ))

        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertEqual(entry.createdAt, Date(timeIntervalSince1970: 300))
        XCTAssertEqual(entry.activeAppName, "Mail")
        XCTAssertEqual(entry.activeAppBundleID, "com.apple.mail")
        XCTAssertEqual(entry.mode, CleanupMode.email.rawValue)
        XCTAssertEqual(entry.rawTranscript, "raw")
        XCTAssertEqual(entry.finalText, "final")
        XCTAssertEqual(entry.durationMS, 42)
        XCTAssertEqual(entry.modelName, "small")
        XCTAssertEqual(entry.language, "en")
        XCTAssertEqual(try store.list(), [entry])
    }

    func testRecorderThrowsWhenEnabledAndHistoryStoreUnavailable() throws {
        var settings = AppSettings.default
        settings.storeHistory = true
        let recorder = DictationHistoryRecorder(
            settingsProvider: { settings },
            historyStore: nil
        )

        XCTAssertThrowsError(try recorder.record(
            rawTranscript: "raw",
            finalText: "final",
            durationMS: 42,
            activeApp: nil,
            mode: .clean,
            modelName: "base",
            language: "en"
        )) { error in
            XCTAssertEqual(error as? DictationHistoryRecorder.RecorderError, .historyUnavailable)
        }
    }

    private func makeEntry(
        createdAt: Date = Date(timeIntervalSince1970: 100),
        rawTranscript: String = "raw words",
        finalText: String = "Final words."
    ) -> NewHistoryEntry {
        NewHistoryEntry(
            createdAt: createdAt,
            activeAppName: "Notes",
            activeAppBundleID: "com.apple.Notes",
            mode: CleanupMode.clean.rawValue,
            rawTranscript: rawTranscript,
            finalText: finalText,
            durationMS: 1234,
            modelName: "base",
            language: "auto"
        )
    }
}
