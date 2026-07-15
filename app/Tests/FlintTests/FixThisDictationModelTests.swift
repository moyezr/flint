import XCTest
@testable import Flint

@MainActor
final class FixThisDictationModelTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-fix-dictation-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testDefaultsToNewestFrozenEntryAndApplicationScope() {
        let older = makeEntry(text: "Older text.", appName: nil, bundleID: nil)
        let newer = makeEntry(
            text: "Use post grass.",
            appName: "Cursor",
            bundleID: "com.todesktop.230313mzl4w4u92"
        )
        let model = makeNoopModel(entries: [newer, older])

        XCTAssertEqual(model.selectedID, newer.id)
        XCTAssertEqual(model.originalText, "Use post grass.")
        XCTAssertEqual(model.correctedText, "Use post grass.")
        XCTAssertEqual(model.scopeKind, .application)
        XCTAssertFalse(model.canSave)

        model.correctedText = "Use Postgres."
        XCTAssertEqual(
            model.proposal,
            CorrectionProposal(heardForm: "post grass", preferredForm: "Postgres")
        )
        XCTAssertTrue(model.includeMapping)
        XCTAssertTrue(model.canSave)

        model.selectedID = older.id
        XCTAssertEqual(model.originalText, "Older text.")
        XCTAssertEqual(model.correctedText, "Older text.")
        XCTAssertEqual(model.scopeKind, .global)
    }

    func testSaveAndCopyPersistsEvidenceAndConfirmedMappingExactlyOnce() async throws {
        let store = LearningStore(databaseURL: tempRoot.appendingPathComponent("Learning.sqlite"))
        let entry = makeEntry(
            text: "Use post grass.",
            appName: "Cursor",
            bundleID: "com.todesktop.230313mzl4w4u92"
        )
        var copied: [String] = []
        var snapshots: [MemorySnapshot] = []
        var dismissCount = 0
        let model = FixThisDictationModel(
            entries: [entry],
            learningStore: store,
            copyAction: { copied.append($0) },
            onLearningChanged: { snapshots.append($0) }
        )
        model.onDismiss = { dismissCount += 1 }
        model.correctedText = "Use Postgres."

        await model.saveAndCopy()

        let memories = try await store.listMemories()
        let evidence = try await store.listEvidence()
        XCTAssertEqual(memories.count, 1)
        XCTAssertEqual(memories.first?.heardForm, "post grass")
        XCTAssertEqual(memories.first?.preferredForm, "Postgres")
        XCTAssertEqual(memories.first?.scopeKind, .application)
        XCTAssertEqual(memories.first?.scopeValue, entry.applicationBundleID)
        XCTAssertEqual(memories.first?.origin, .explicitCorrection)
        XCTAssertEqual(evidence.count, 1)
        XCTAssertEqual(evidence.first?.memoryItemID, memories.first?.id)
        XCTAssertEqual(evidence.first?.originalText, entry.insertedText)
        XCTAssertEqual(evidence.first?.correctedText, "Use Postgres.")
        XCTAssertEqual(copied, ["Use Postgres."])
        XCTAssertEqual(snapshots.last?.memories, memories)
        XCTAssertEqual(dismissCount, 1)
    }

    func testDisablingProposalSavesEvidenceWithoutMemory() async throws {
        let store = LearningStore(databaseURL: tempRoot.appendingPathComponent("Learning.sqlite"))
        let model = FixThisDictationModel(
            entries: [makeEntry(text: "Use post grass.")],
            learningStore: store,
            copyAction: { _ in }
        )
        model.correctedText = "Use Postgres."
        model.includeMapping = false

        await model.saveAndCopy()

        let memories = try await store.listMemories()
        let evidence = try await store.listEvidence()
        XCTAssertTrue(memories.isEmpty)
        XCTAssertEqual(evidence.count, 1)
    }

    func testAmbiguousCommonPhraseSavesEvidenceWithoutBlindReplacement() async throws {
        let store = LearningStore(databaseURL: tempRoot.appendingPathComponent("Learning.sqlite"))
        let model = FixThisDictationModel(
            entries: [makeEntry(text: "We use next year for this project.")],
            learningStore: store,
            copyAction: { _ in }
        )
        model.correctedText = "We use Next.js for this project."

        XCTAssertEqual(
            model.proposal,
            CorrectionProposal(heardForm: "next year", preferredForm: "Next.js")
        )
        XCTAssertEqual(model.mappingSafety, .contextRequired)
        XCTAssertFalse(model.includeMapping)

        await model.saveAndCopy()

        let memories = try await store.listMemories()
        let evidence = try await store.listEvidence()
        XCTAssertTrue(memories.isEmpty)
        XCTAssertEqual(evidence.count, 1)
    }

    func testIneligibleRewriteSavesEvidenceOnly() async throws {
        let store = LearningStore(databaseURL: tempRoot.appendingPathComponent("Learning.sqlite"))
        let model = FixThisDictationModel(
            entries: [makeEntry(text: "alpha stays omega")],
            learningStore: store,
            copyAction: { _ in }
        )
        model.correctedText = "ALPHA stays OMEGA"

        XCTAssertNil(model.proposal)
        await model.saveAndCopy()

        let memories = try await store.listMemories()
        let evidence = try await store.listEvidence()
        XCTAssertTrue(memories.isEmpty)
        XCTAssertEqual(evidence.count, 1)
    }

    func testPersistenceFailurePreservesCorrectionAndDoesNotCopyOrDismiss() async {
        var copied: [String] = []
        var dismissCount = 0
        let model = FixThisDictationModel(
            entries: [makeEntry(text: "Use post grass.")],
            saveAction: { _ in throw TestError.persistenceFailed },
            copyAction: { copied.append($0) }
        )
        model.onDismiss = { dismissCount += 1 }
        model.correctedText = "Use Postgres."

        await model.saveAndCopy()

        XCTAssertEqual(model.correctedText, "Use Postgres.")
        XCTAssertEqual(model.errorMessage, "Persistence failed")
        XCTAssertTrue(copied.isEmpty)
        XCTAssertEqual(dismissCount, 0)
    }

    func testEmptyCorrectionCannotBeSaved() {
        let model = makeNoopModel(entries: [makeEntry(text: "Some text")])
        model.correctedText = "   "
        XCTAssertFalse(model.canSave)
        XCTAssertNil(model.proposal)
    }

    private func makeNoopModel(entries: [RecentDictation]) -> FixThisDictationModel {
        FixThisDictationModel(
            entries: entries,
            saveAction: { write in
                ExplicitCorrectionWriteResult(
                    memory: nil,
                    evidence: CorrectionEvidence(
                        id: UUID(),
                        memoryItemID: nil,
                        originalText: write.evidence.originalText,
                        correctedText: write.evidence.correctedText,
                        applicationBundleID: write.evidence.applicationBundleID,
                        language: write.evidence.language,
                        cleanupMode: write.evidence.cleanupMode,
                        source: .explicitFix,
                        createdAt: write.evidence.createdAt
                    )
                )
            }
        )
    }

    private func makeEntry(
        text: String,
        appName: String? = "Notes",
        bundleID: String? = "com.apple.Notes"
    ) -> RecentDictation {
        RecentDictation(
            rawText: text,
            insertedText: text,
            applicationName: appName,
            applicationBundleID: bundleID,
            language: "en",
            cleanupMode: .clean,
            deliveryResult: .inserted
        )
    }

    private enum TestError: LocalizedError {
        case persistenceFailed

        var errorDescription: String? { "Persistence failed" }
    }
}
