import XCTest
@testable import Flint

final class LearningStoreTests: XCTestCase {
    private var tempRoot: URL!
    private var databaseURL: URL!
    private var defaultsSuite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-learning-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        databaseURL = tempRoot.appendingPathComponent("Learning.sqlite")
        defaultsSuite = "FlintTests.LearningStore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)!
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    override func tearDownWithError() throws {
        if let defaultsSuite { defaults?.removePersistentDomain(forName: defaultsSuite) }
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        defaults = nil
        defaultsSuite = nil
        databaseURL = nil
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testSchemaCreationAndGlobalUpsertUseOneNormalizedKey() async throws {
        let store = makeStore()
        try await store.migrate()
        let first = try await store.upsertMemory(LearningMemoryDraft(
            heardForm: "  Live   Kit ",
            preferredForm: "LiveKit"
        ))
        let second = try await store.upsertMemory(LearningMemoryDraft(
            heardForm: "live kit",
            preferredForm: "LIVEKIT"
        ))

        let memories = try await store.listMemories()
        XCTAssertTrue(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(second.heardKey, "live kit")
        XCTAssertEqual(second.preferredForm, "LIVEKIT")
        XCTAssertEqual(second.scopeValue, "")
    }

    func testApplicationScopeCanCoexistWithGlobalScope() async throws {
        let store = makeStore()
        _ = try await store.upsertMemory(LearningMemoryDraft(
            heardForm: "flask",
            preferredForm: "Flask"
        ))
        _ = try await store.upsertMemory(LearningMemoryDraft(
            heardForm: "flask",
            preferredForm: "FLASK",
            scopeKind: .application,
            scopeValue: "com.microsoft.VSCode"
        ))

        let memories = try await store.listMemories()
        XCTAssertEqual(memories.count, 2)
        XCTAssertEqual(Set(memories.map(\.scopeKind)), [.global, .application])
    }

    func testApplicationScopeRequiresBundleIdentifier() async throws {
        let store = makeStore()
        do {
            _ = try await store.upsertMemory(LearningMemoryDraft(
                heardForm: "flask",
                preferredForm: "Flask",
                scopeKind: .application
            ))
            XCTFail("Expected validation to fail")
        } catch {
            XCTAssertEqual(
                error as? LearningStore.StoreError,
                .invalidMemory("Application-scoped vocabulary requires a bundle identifier.")
            )
        }
    }

    func testExplicitCorrectionAtomicallyLinksEvidenceAndMemory() async throws {
        let store = makeStore()
        let result = try await store.saveExplicitCorrection(ExplicitCorrectionWrite(
            memory: LearningMemoryDraft(
                heardForm: "post grass",
                preferredForm: "Postgres",
                scopeKind: .application,
                scopeValue: "com.todesktop.230313mzl4w4u92",
                origin: .explicitCorrection
            ),
            evidence: CorrectionEvidenceDraft(
                originalText: "Use post grass for this.",
                correctedText: "Use Postgres for this.",
                applicationBundleID: "com.todesktop.230313mzl4w4u92",
                cleanupMode: .clean
            )
        ))

        let evidence = try await store.listEvidence()
        XCTAssertEqual(evidence.count, 1)
        XCTAssertEqual(evidence[0].memoryItemID, result.memory?.id)
        XCTAssertEqual(evidence[0].originalText, "Use post grass for this.")

        if let memoryID = result.memory?.id {
            try await store.deleteMemory(id: memoryID)
        }
        let evidenceAfterDeletion = try await store.listEvidence()
        XCTAssertNil(evidenceAfterDeletion.first?.memoryItemID)
    }

    func testFailedCorrectionDoesNotLeaveMemoryBehind() async throws {
        let store = makeStore()
        do {
            _ = try await store.saveExplicitCorrection(ExplicitCorrectionWrite(
                memory: LearningMemoryDraft(heardForm: "post grass", preferredForm: "Postgres"),
                evidence: CorrectionEvidenceDraft(
                    originalText: "unchanged",
                    correctedText: "unchanged"
                )
            ))
            XCTFail("Expected validation to fail")
        } catch {
            let memories = try await store.listMemories()
            let evidence = try await store.listEvidence()
            XCTAssertTrue(memories.isEmpty)
            XCTAssertTrue(evidence.isEmpty)
        }
    }

    func testLegacyMigrationIsVerifiedIdempotentAndPreservesMetadata() async throws {
        let store = makeStore()
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let updatedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let replacement = DictionaryReplacement(
            id: id,
            heardPhrase: "live kit",
            preferredReplacement: "LiveKit",
            usageCount: 7,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        defaults.set(Data([1, 2, 3]), forKey: "dictionary.customReplacements")

        let firstCount = try await store.migrateLegacyVocabulary([replacement], userDefaults: defaults)
        let secondCount = try await store.migrateLegacyVocabulary([replacement], userDefaults: defaults)
        let memories = try await store.listMemories()
        let memory = try XCTUnwrap(memories.first)

        XCTAssertEqual(firstCount, 1)
        XCTAssertEqual(secondCount, 0)
        XCTAssertTrue(defaults.bool(forKey: LearningStore.legacyVocabularyMigrationKey))
        XCTAssertNotNil(defaults.data(forKey: "dictionary.customReplacements"))
        XCTAssertEqual(memory.id, id)
        XCTAssertEqual(memory.usageCount, 7)
        XCTAssertEqual(memory.createdAt.timeIntervalSince1970, createdAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertEqual(memory.updatedAt.timeIntervalSince1970, updatedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testRetentionPrunesEvidenceByAgeAndCountWithoutPruningMemories() async throws {
        let policy = LearningRetentionPolicy(
            evidenceMaxAge: 100,
            evidenceMaxCount: 2,
            databaseHighWaterBytes: 50 * 1_024 * 1_024
        )
        let store = makeStore(retentionPolicy: policy)
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        for (index, age) in [200.0, 50.0, 10.0, 0.0].enumerated() {
            _ = try await store.saveExplicitCorrection(ExplicitCorrectionWrite(
                memory: index == 0
                    ? LearningMemoryDraft(heardForm: "term zero", preferredForm: "TermZero")
                    : nil,
                evidence: CorrectionEvidenceDraft(
                    originalText: "wrong \(index)",
                    correctedText: "right \(index)",
                    createdAt: now.addingTimeInterval(-age)
                )
            ))
        }
        try await store.runRetention(now: now)

        let evidence = try await store.listEvidence(limit: 10)
        let memories = try await store.listMemories()
        XCTAssertEqual(evidence.map(\.correctedText), ["right 3", "right 2"])
        XCTAssertEqual(memories.count, 1)
    }

    func testHighWaterPolicyDropsEvidenceBeforeUserMemory() async throws {
        let store = makeStore(retentionPolicy: LearningRetentionPolicy(
            evidenceMaxAge: 10_000,
            evidenceMaxCount: 100,
            databaseHighWaterBytes: 1
        ))
        _ = try await store.saveExplicitCorrection(ExplicitCorrectionWrite(
            memory: LearningMemoryDraft(heardForm: "post grass", preferredForm: "Postgres"),
            evidence: CorrectionEvidenceDraft(originalText: "post grass", correctedText: "Postgres")
        ))

        let evidence = try await store.listEvidence()
        let memories = try await store.listMemories()
        XCTAssertTrue(evidence.isEmpty)
        XCTAssertEqual(memories.count, 1)
    }

    func testUsageCountsAreUpdatedOffSnapshotPath() async throws {
        let store = makeStore()
        let memory = try await store.upsertMemory(LearningMemoryDraft(
            heardForm: "post grass",
            preferredForm: "Postgres"
        ))
        let usedAt = Date(timeIntervalSince1970: 1_700_000_000)
        try await store.incrementUsageCounts([memory.id: 3], usedAt: usedAt)

        let memories = try await store.listMemories()
        let updated = try XCTUnwrap(memories.first)
        let lastUsedAt = try XCTUnwrap(updated.lastUsedAt)
        XCTAssertEqual(updated.usageCount, 3)
        XCTAssertEqual(lastUsedAt.timeIntervalSince1970, usedAt.timeIntervalSince1970, accuracy: 0.001)
    }

    func testDeleteDatabaseFilesRemovesDatabaseWALAndSHM() async throws {
        let store = makeStore()
        try await store.migrate()
        let walURL = URL(fileURLWithPath: databaseURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: databaseURL.path + "-shm")
        FileManager.default.createFile(atPath: walURL.path, contents: Data([1]))
        FileManager.default.createFile(atPath: shmURL.path, contents: Data([2]))

        try await store.deleteDatabaseFiles()

        XCTAssertFalse(FileManager.default.fileExists(atPath: databaseURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: walURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shmURL.path))
    }

    private func makeStore(
        retentionPolicy: LearningRetentionPolicy = .default
    ) -> LearningStore {
        LearningStore(databaseURL: databaseURL, retentionPolicy: retentionPolicy)
    }
}
