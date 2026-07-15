import Foundation
import SQLite3

actor LearningStore {
    enum StoreError: LocalizedError, Equatable {
        case sqlite(message: String)
        case invalidMemory(String)
        case invalidEvidence(String)
        case invalidStoredValue(String)

        var errorDescription: String? {
            switch self {
            case .sqlite(let message):
                return message
            case .invalidMemory(let message), .invalidEvidence(let message):
                return message
            case .invalidStoredValue(let value):
                return "Learning data contains an unsupported value: \(value)"
            }
        }
    }

    static let legacyVocabularyMigrationKey = "learning.migratedLegacyVocabulary.v1"

    nonisolated let databaseURL: URL

    private let fileManager: FileManager
    private let retentionPolicy: LearningRetentionPolicy

    init(
        databaseURL: URL = LearningStore.defaultDatabaseURL(),
        fileManager: FileManager = .default,
        retentionPolicy: LearningRetentionPolicy = .default
    ) {
        self.databaseURL = databaseURL
        self.fileManager = fileManager
        self.retentionPolicy = retentionPolicy
    }

    static func defaultDatabaseURL() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)

        return applicationSupport
            .appendingPathComponent("Flint", isDirectory: true)
            .appendingPathComponent("Learning.sqlite")
    }

    func migrate() throws {
        let db = try openDatabase()
        sqlite3_close(db)
    }

    @discardableResult
    func upsertMemory(
        _ unnormalizedDraft: LearningMemoryDraft,
        id: UUID = UUID(),
        createdAt: Date = Date(),
        usageCount: Int = 0,
        updatedAt: Date = Date()
    ) throws -> LearningMemory {
        let draft = try validated(unnormalizedDraft)
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        return try upsertMemory(
            draft,
            id: id,
            createdAt: createdAt,
            usageCount: usageCount,
            updatedAt: updatedAt,
            db: db
        )
    }

    func listMemories(includeInactive: Bool = true) throws -> [LearningMemory] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let predicate = includeInactive ? "" : "WHERE status = 'active'"
        let statement = try prepare(
            """
            SELECT id, memory_type, scope_kind, scope_value, language,
                   heard_form, heard_key, preferred_form, confidence,
                   evidence_count, usage_count, status, origin,
                   created_at, updated_at, last_used_at
            FROM memory_items
            \(predicate)
            ORDER BY updated_at DESC, id ASC;
            """,
            db: db
        )
        defer { sqlite3_finalize(statement) }

        var memories: [LearningMemory] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            memories.append(try readMemory(statement))
        }
        return memories
    }

    func memorySnapshot() throws -> MemorySnapshot {
        MemorySnapshot(memories: try listMemories(includeInactive: false))
    }

    func listEvidence(limit: Int = 100) throws -> [CorrectionEvidence] {
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        let statement = try prepare(
            """
            SELECT id, memory_item_id, original_text, corrected_text,
                   application_bundle_id, language, cleanup_mode, source, created_at
            FROM correction_evidence
            ORDER BY created_at DESC, id DESC
            LIMIT ?;
            """,
            db: db
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(max(0, limit)))

        var evidence: [CorrectionEvidence] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            evidence.append(try readEvidence(statement))
        }
        return evidence
    }

    @discardableResult
    func saveExplicitCorrection(_ write: ExplicitCorrectionWrite) throws -> ExplicitCorrectionWriteResult {
        let evidenceDraft = try validated(write.evidence)
        let memoryDraft = try write.memory.map(validated)
        let db = try openDatabase()
        defer { sqlite3_close(db) }

        try execute("BEGIN IMMEDIATE TRANSACTION;", db: db)
        do {
            let memory = try memoryDraft.map {
                try upsertMemory($0, id: UUID(), createdAt: Date(), usageCount: 0, updatedAt: Date(), db: db)
            }
            let evidence = try insertEvidence(evidenceDraft, memoryItemID: memory?.id, db: db)
            try pruneEvidence(now: evidenceDraft.createdAt, db: db)
            try execute("COMMIT;", db: db)
            try checkpointIfNeeded(db: db)
            return ExplicitCorrectionWriteResult(memory: memory, evidence: evidence)
        } catch {
            try? execute("ROLLBACK;", db: db)
            throw error
        }
    }

    @discardableResult
    func migrateLegacyVocabulary(
        _ replacements: [DictionaryReplacement],
        userDefaults: UserDefaults,
        markerKey: String = LearningStore.legacyVocabularyMigrationKey
    ) throws -> Int {
        guard !userDefaults.bool(forKey: markerKey) else { return 0 }

        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try execute("BEGIN IMMEDIATE TRANSACTION;", db: db)

        do {
            for replacement in replacements {
                let draft = try validated(LearningMemoryDraft(
                    heardForm: replacement.heardPhrase,
                    preferredForm: replacement.preferredReplacement,
                    scopeKind: .global,
                    scopeValue: "",
                    language: "auto",
                    status: .active,
                    origin: .seeded
                ))
                _ = try upsertMemory(
                    draft,
                    id: replacement.id,
                    createdAt: replacement.createdAt,
                    usageCount: replacement.usageCount,
                    updatedAt: replacement.updatedAt,
                    db: db
                )
            }
            try execute("COMMIT;", db: db)
        } catch {
            try? execute("ROLLBACK;", db: db)
            throw error
        }

        let activeKeys = try loadActiveKeys(db: db)
        let expectedKeys = Set(replacements.map { VocabularyNormalizer.key(for: $0.heardPhrase) })
        guard expectedKeys.isSubset(of: activeKeys) else {
            throw StoreError.sqlite(message: "Legacy vocabulary was written but could not be verified.")
        }

        // The legacy payload intentionally remains in UserDefaults for rollback safety.
        userDefaults.set(true, forKey: markerKey)
        return replacements.count
    }

    func incrementUsageCounts(_ counts: [UUID: Int], usedAt: Date = Date()) throws {
        let positiveCounts = counts.filter { $0.value > 0 }
        guard !positiveCounts.isEmpty else { return }

        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try execute("BEGIN IMMEDIATE TRANSACTION;", db: db)
        do {
            let statement = try prepare(
                """
                UPDATE memory_items
                SET usage_count = usage_count + ?, updated_at = ?, last_used_at = ?
                WHERE id = ?;
                """,
                db: db
            )
            defer { sqlite3_finalize(statement) }

            for (id, count) in positiveCounts {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_int64(statement, 1, Int64(count))
                sqlite3_bind_int64(statement, 2, Self.timestamp(usedAt))
                sqlite3_bind_int64(statement, 3, Self.timestamp(usedAt))
                bind(id.uuidString, at: 4, statement: statement)
                try stepDone(statement, db: db)
            }
            try execute("COMMIT;", db: db)
        } catch {
            try? execute("ROLLBACK;", db: db)
            throw error
        }
    }

    func deleteMemory(id: UUID) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        let statement = try prepare("DELETE FROM memory_items WHERE id = ?;", db: db)
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, at: 1, statement: statement)
        try stepDone(statement, db: db)
    }

    func deleteCorrectionEvidence() throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try execute("DELETE FROM correction_evidence;", db: db)
        try checkpointIfNeeded(db: db)
    }

    func deleteAllLearningData() throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try execute("BEGIN IMMEDIATE TRANSACTION;", db: db)
        do {
            try execute("DELETE FROM correction_evidence;", db: db)
            try execute("DELETE FROM memory_items;", db: db)
            try execute("COMMIT;", db: db)
            try checkpointIfNeeded(db: db)
        } catch {
            try? execute("ROLLBACK;", db: db)
            throw error
        }
    }

    func deleteDatabaseFiles() throws {
        for url in databaseFileURLs() where fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    func summary() throws -> LearningStoreSummary {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        return LearningStoreSummary(
            activeMemoryCount: try scalarCount("SELECT COUNT(*) FROM memory_items WHERE status = 'active';", db: db),
            evidenceCount: try scalarCount("SELECT COUNT(*) FROM correction_evidence;", db: db),
            databaseSizeBytes: databaseSizeBytes()
        )
    }

    func runRetention(now: Date = Date()) throws {
        let db = try openDatabase()
        defer { sqlite3_close(db) }
        try execute("BEGIN IMMEDIATE TRANSACTION;", db: db)
        do {
            try pruneEvidence(now: now, db: db)
            try execute("COMMIT;", db: db)
            try checkpointIfNeeded(db: db)
        } catch {
            try? execute("ROLLBACK;", db: db)
            throw error
        }
    }

    private func openDatabase() throws -> OpaquePointer? {
        try fileManager.createDirectory(
            at: databaseURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(databaseURL.path, &db, flags, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unable to open Learning.sqlite."
            if let db { sqlite3_close(db) }
            throw StoreError.sqlite(message: message)
        }

        do {
            sqlite3_busy_timeout(db, 2_000)
            try execute("PRAGMA foreign_keys = ON;", db: db)
            try execute("PRAGMA journal_mode = WAL;", db: db)
            try createSchema(db: db)
            return db
        } catch {
            sqlite3_close(db)
            throw error
        }
    }

    private func createSchema(db: OpaquePointer?) throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS memory_items (
                id TEXT PRIMARY KEY,
                memory_type TEXT NOT NULL DEFAULT 'vocabulary' CHECK (memory_type = 'vocabulary'),
                scope_kind TEXT NOT NULL CHECK (scope_kind IN ('global', 'application')),
                scope_value TEXT NOT NULL DEFAULT '',
                language TEXT NOT NULL DEFAULT 'auto',
                heard_form TEXT NOT NULL,
                heard_key TEXT NOT NULL,
                preferred_form TEXT NOT NULL,
                confidence REAL NOT NULL DEFAULT 1.0,
                evidence_count INTEGER NOT NULL DEFAULT 1,
                usage_count INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('proposed', 'active', 'disabled', 'rejected')),
                origin TEXT NOT NULL CHECK (origin IN ('seeded', 'explicit_correction')),
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL,
                last_used_at INTEGER,
                CHECK (
                    (scope_kind = 'global' AND scope_value = '') OR
                    (scope_kind = 'application' AND length(scope_value) > 0)
                )
            );
            """,
            db: db
        )
        try execute(
            """
            CREATE UNIQUE INDEX IF NOT EXISTS idx_memory_unique_mapping
            ON memory_items(memory_type, scope_kind, scope_value, language, heard_key);
            """,
            db: db
        )
        try execute(
            """
            CREATE INDEX IF NOT EXISTS idx_memory_active_scope
            ON memory_items(status, language, scope_kind, scope_value);
            """,
            db: db
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS correction_evidence (
                id TEXT PRIMARY KEY,
                memory_item_id TEXT REFERENCES memory_items(id) ON DELETE SET NULL,
                original_text TEXT NOT NULL,
                corrected_text TEXT NOT NULL,
                application_bundle_id TEXT NOT NULL DEFAULT '',
                language TEXT NOT NULL DEFAULT 'auto',
                cleanup_mode TEXT,
                source TEXT NOT NULL DEFAULT 'explicit_fix' CHECK (source = 'explicit_fix'),
                created_at INTEGER NOT NULL
            );
            """,
            db: db
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS idx_evidence_memory_item ON correction_evidence(memory_item_id);",
            db: db
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS idx_evidence_created_at ON correction_evidence(created_at);",
            db: db
        )
        try execute("PRAGMA user_version = 1;", db: db)
    }

    private func validated(_ draft: LearningMemoryDraft) throws -> LearningMemoryDraft {
        let draft = draft.normalized
        guard !draft.heardForm.isEmpty, !draft.preferredForm.isEmpty else {
            throw StoreError.invalidMemory("Heard and preferred forms are required.")
        }
        guard draft.heardForm != draft.preferredForm else {
            throw StoreError.invalidMemory("Heard and preferred forms must be different.")
        }
        guard draft.scopeKind != .application || !draft.scopeValue.isEmpty else {
            throw StoreError.invalidMemory("Application-scoped vocabulary requires a bundle identifier.")
        }
        guard draft.confidence.isFinite, draft.confidence >= 0, draft.evidenceCount >= 0 else {
            throw StoreError.invalidMemory("Vocabulary confidence and evidence count must be valid.")
        }
        return draft
    }

    private func validated(_ draft: CorrectionEvidenceDraft) throws -> CorrectionEvidenceDraft {
        guard !draft.originalText.isEmpty, draft.originalText != draft.correctedText else {
            throw StoreError.invalidEvidence("An explicit correction must change non-empty Flint output.")
        }
        var normalized = draft
        normalized.applicationBundleID = draft.applicationBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let language = draft.language.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.language = language.isEmpty ? "auto" : language
        return normalized
    }

    private func upsertMemory(
        _ draft: LearningMemoryDraft,
        id: UUID,
        createdAt: Date,
        usageCount: Int,
        updatedAt: Date,
        db: OpaquePointer?
    ) throws -> LearningMemory {
        let statement = try prepare(
            """
            INSERT INTO memory_items (
                id, memory_type, scope_kind, scope_value, language,
                heard_form, heard_key, preferred_form, confidence,
                evidence_count, usage_count, status, origin, created_at, updated_at
            ) VALUES (?, 'vocabulary', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(memory_type, scope_kind, scope_value, language, heard_key)
            DO UPDATE SET
                heard_form = excluded.heard_form,
                preferred_form = excluded.preferred_form,
                confidence = excluded.confidence,
                evidence_count = MAX(memory_items.evidence_count, excluded.evidence_count),
                usage_count = MAX(memory_items.usage_count, excluded.usage_count),
                status = excluded.status,
                origin = excluded.origin,
                updated_at = excluded.updated_at;
            """,
            db: db
        )
        defer { sqlite3_finalize(statement) }

        bind(id.uuidString, at: 1, statement: statement)
        bind(draft.scopeKind.rawValue, at: 2, statement: statement)
        bind(draft.scopeValue, at: 3, statement: statement)
        bind(draft.language, at: 4, statement: statement)
        bind(draft.heardForm, at: 5, statement: statement)
        bind(VocabularyNormalizer.key(for: draft.heardForm), at: 6, statement: statement)
        bind(draft.preferredForm, at: 7, statement: statement)
        sqlite3_bind_double(statement, 8, draft.confidence)
        sqlite3_bind_int64(statement, 9, Int64(draft.evidenceCount))
        sqlite3_bind_int64(statement, 10, Int64(max(0, usageCount)))
        bind(draft.status.rawValue, at: 11, statement: statement)
        bind(draft.origin.rawValue, at: 12, statement: statement)
        sqlite3_bind_int64(statement, 13, Self.timestamp(createdAt))
        sqlite3_bind_int64(statement, 14, Self.timestamp(updatedAt))
        try stepDone(statement, db: db)

        return try memory(
            scopeKind: draft.scopeKind,
            scopeValue: draft.scopeValue,
            language: draft.language,
            heardKey: VocabularyNormalizer.key(for: draft.heardForm),
            db: db
        )
    }

    private func memory(
        scopeKind: LearningScopeKind,
        scopeValue: String,
        language: String,
        heardKey: String,
        db: OpaquePointer?
    ) throws -> LearningMemory {
        let statement = try prepare(
            """
            SELECT id, memory_type, scope_kind, scope_value, language,
                   heard_form, heard_key, preferred_form, confidence,
                   evidence_count, usage_count, status, origin,
                   created_at, updated_at, last_used_at
            FROM memory_items
            WHERE memory_type = 'vocabulary' AND scope_kind = ? AND scope_value = ?
                  AND language = ? AND heard_key = ?
            LIMIT 1;
            """,
            db: db
        )
        defer { sqlite3_finalize(statement) }
        bind(scopeKind.rawValue, at: 1, statement: statement)
        bind(scopeValue, at: 2, statement: statement)
        bind(language, at: 3, statement: statement)
        bind(heardKey, at: 4, statement: statement)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw sqliteError(db) }
        return try readMemory(statement)
    }

    private func insertEvidence(
        _ draft: CorrectionEvidenceDraft,
        memoryItemID: UUID?,
        db: OpaquePointer?
    ) throws -> CorrectionEvidence {
        let id = UUID()
        let statement = try prepare(
            """
            INSERT INTO correction_evidence (
                id, memory_item_id, original_text, corrected_text,
                application_bundle_id, language, cleanup_mode, source, created_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
            """,
            db: db
        )
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, at: 1, statement: statement)
        bind(memoryItemID?.uuidString, at: 2, statement: statement)
        bind(draft.originalText, at: 3, statement: statement)
        bind(draft.correctedText, at: 4, statement: statement)
        bind(draft.applicationBundleID, at: 5, statement: statement)
        bind(draft.language, at: 6, statement: statement)
        bind(draft.cleanupMode?.rawValue, at: 7, statement: statement)
        bind(draft.source.rawValue, at: 8, statement: statement)
        sqlite3_bind_int64(statement, 9, Self.timestamp(draft.createdAt))
        try stepDone(statement, db: db)
        return CorrectionEvidence(
            id: id,
            memoryItemID: memoryItemID,
            originalText: draft.originalText,
            correctedText: draft.correctedText,
            applicationBundleID: draft.applicationBundleID,
            language: draft.language,
            cleanupMode: draft.cleanupMode,
            source: draft.source,
            createdAt: draft.createdAt
        )
    }

    private func pruneEvidence(now: Date, db: OpaquePointer?) throws {
        let cutoff = retentionPolicy.evidenceCutoffDate(relativeTo: now)
        let ageStatement = try prepare("DELETE FROM correction_evidence WHERE created_at < ?;", db: db)
        sqlite3_bind_int64(ageStatement, 1, Self.timestamp(cutoff))
        defer { sqlite3_finalize(ageStatement) }
        try stepDone(ageStatement, db: db)

        let overflow = max(
            0,
            try scalarCount("SELECT COUNT(*) FROM correction_evidence;", db: db) - max(0, retentionPolicy.evidenceMaxCount)
        )
        if overflow > 0 {
            let countStatement = try prepare(
                """
                DELETE FROM correction_evidence WHERE id IN (
                    SELECT id FROM correction_evidence ORDER BY created_at ASC, id ASC LIMIT ?
                );
                """,
                db: db
            )
            defer { sqlite3_finalize(countStatement) }
            sqlite3_bind_int64(countStatement, 1, Int64(overflow))
            try stepDone(countStatement, db: db)
        }

        if databaseSizeBytes() > retentionPolicy.databaseHighWaterBytes {
            // Content is bounded immediately. SQLite can reuse the released pages without a blocking VACUUM.
            try execute("DELETE FROM correction_evidence;", db: db)
        }
    }

    private func checkpointIfNeeded(db: OpaquePointer?) throws {
        guard databaseSizeBytes() > retentionPolicy.databaseHighWaterBytes else { return }
        var logFrames: Int32 = 0
        var checkpointedFrames: Int32 = 0
        let result = sqlite3_wal_checkpoint_v2(
            db,
            nil,
            SQLITE_CHECKPOINT_PASSIVE,
            &logFrames,
            &checkpointedFrames
        )
        guard result == SQLITE_OK || result == SQLITE_BUSY else { throw sqliteError(db) }
    }

    private func loadActiveKeys(db: OpaquePointer?) throws -> Set<String> {
        let statement = try prepare(
            "SELECT heard_key FROM memory_items WHERE status = 'active';",
            db: db
        )
        defer { sqlite3_finalize(statement) }
        var result: Set<String> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let key = string(at: 0, statement: statement) { result.insert(key) }
        }
        return result
    }

    private func readMemory(_ statement: OpaquePointer?) throws -> LearningMemory {
        guard let idValue = string(at: 0, statement: statement), let id = UUID(uuidString: idValue),
              let typeValue = string(at: 1, statement: statement), let type = LearningMemoryType(rawValue: typeValue),
              let scopeValue = string(at: 2, statement: statement), let scope = LearningScopeKind(rawValue: scopeValue),
              let statusValue = string(at: 11, statement: statement), let status = LearningMemoryStatus(rawValue: statusValue),
              let originValue = string(at: 12, statement: statement), let origin = LearningMemoryOrigin(rawValue: originValue)
        else {
            throw StoreError.invalidStoredValue("memory_items")
        }

        return LearningMemory(
            id: id,
            memoryType: type,
            scopeKind: scope,
            scopeValue: string(at: 3, statement: statement) ?? "",
            language: string(at: 4, statement: statement) ?? "auto",
            heardForm: string(at: 5, statement: statement) ?? "",
            heardKey: string(at: 6, statement: statement) ?? "",
            preferredForm: string(at: 7, statement: statement) ?? "",
            confidence: sqlite3_column_double(statement, 8),
            evidenceCount: Int(sqlite3_column_int64(statement, 9)),
            usageCount: Int(sqlite3_column_int64(statement, 10)),
            status: status,
            origin: origin,
            createdAt: Self.date(sqlite3_column_int64(statement, 13)),
            updatedAt: Self.date(sqlite3_column_int64(statement, 14)),
            lastUsedAt: sqlite3_column_type(statement, 15) == SQLITE_NULL
                ? nil
                : Self.date(sqlite3_column_int64(statement, 15))
        )
    }

    private func readEvidence(_ statement: OpaquePointer?) throws -> CorrectionEvidence {
        guard let idValue = string(at: 0, statement: statement), let id = UUID(uuidString: idValue),
              let sourceValue = string(at: 7, statement: statement), let source = CorrectionEvidenceSource(rawValue: sourceValue)
        else {
            throw StoreError.invalidStoredValue("correction_evidence")
        }
        let memoryID = string(at: 1, statement: statement).flatMap(UUID.init(uuidString:))
        let mode = string(at: 6, statement: statement).flatMap(CleanupMode.init(rawValue:))
        return CorrectionEvidence(
            id: id,
            memoryItemID: memoryID,
            originalText: string(at: 2, statement: statement) ?? "",
            correctedText: string(at: 3, statement: statement) ?? "",
            applicationBundleID: string(at: 4, statement: statement) ?? "",
            language: string(at: 5, statement: statement) ?? "auto",
            cleanupMode: mode,
            source: source,
            createdAt: Self.date(sqlite3_column_int64(statement, 8))
        )
    }

    private func prepare(_ sql: String, db: OpaquePointer?) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw sqliteError(db)
        }
        return statement
    }

    private func execute(_ sql: String, db: OpaquePointer?) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? String(cString: sqlite3_errmsg(db))
            sqlite3_free(errorMessage)
            throw StoreError.sqlite(message: message)
        }
    }

    private func stepDone(_ statement: OpaquePointer?, db: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else { throw sqliteError(db) }
    }

    private func scalarCount(_ sql: String, db: OpaquePointer?) throws -> Int {
        let statement = try prepare(sql, db: db)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw sqliteError(db) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func bind(_ value: String?, at index: Int32, statement: OpaquePointer?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, learningSQLiteTransient)
    }

    private func string(at column: Int32, statement: OpaquePointer?) -> String? {
        guard sqlite3_column_type(statement, column) != SQLITE_NULL,
              let value = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: value)
    }

    private func sqliteError(_ db: OpaquePointer?) -> StoreError {
        StoreError.sqlite(message: String(cString: sqlite3_errmsg(db)))
    }

    private func databaseFileURLs() -> [URL] {
        [
            databaseURL,
            URL(fileURLWithPath: databaseURL.path + "-wal"),
            URL(fileURLWithPath: databaseURL.path + "-shm")
        ]
    }

    private func databaseSizeBytes() -> Int64 {
        databaseFileURLs().reduce(0) { result, url in
            guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
                  let size = attributes[.size] as? NSNumber else { return result }
            return result + size.int64Value
        }
    }

    private static func timestamp(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1_000).rounded())
    }

    private static func date(_ timestamp: Int64) -> Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1_000)
    }
}

private let learningSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
