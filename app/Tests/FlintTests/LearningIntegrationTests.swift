import XCTest
@testable import Flint

final class LearningIntegrationTests: XCTestCase {
    private var tempRoot: URL!
    private var defaultsSuite: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-learning-integration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defaultsSuite = "FlintTests.LearningIntegration.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuite)!
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    override func tearDownWithError() throws {
        if let defaultsSuite { defaults?.removePersistentDomain(forName: defaultsSuite) }
        if let tempRoot { try? FileManager.default.removeItem(at: tempRoot) }
        defaults = nil
        defaultsSuite = nil
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testLegacyMigrationAffectsNextSnapshotBasedDictationWithoutRemovingRollbackData() async throws {
        let dictionary = DictionaryEngine(userDefaults: defaults)
        _ = dictionary.addReplacement(heardPhrase: "live kit", preferredReplacement: "LiveKit")
        let store = makeStore()

        _ = try await store.migrateLegacyVocabulary(
            dictionary.listCustomReplacements(),
            userDefaults: defaults
        )
        let snapshot = try await store.memorySnapshot()
        let result = dictionary.apply(
            to: "Use live kit today",
            snapshot: snapshot,
            activeApp: nil,
            language: "auto"
        )

        XCTAssertEqual(result.text, "Use LiveKit today")
        XCTAssertEqual(result.matchedMemoryCounts.values.reduce(0, +), 1)
        XCTAssertEqual(dictionary.listCustomReplacements().count, 1)
    }

    func testConfirmedExplicitCorrectionAffectsMatchingAppOnly() async throws {
        let store = makeStore()
        _ = try await store.saveExplicitCorrection(ExplicitCorrectionWrite(
            memory: LearningMemoryDraft(
                heardForm: "post grass",
                preferredForm: "Postgres",
                scopeKind: .application,
                scopeValue: "com.microsoft.VSCode",
                origin: .explicitCorrection
            ),
            evidence: CorrectionEvidenceDraft(
                originalText: "Use post grass.",
                correctedText: "Use Postgres.",
                applicationBundleID: "com.microsoft.VSCode"
            )
        ))
        let snapshot = try await store.memorySnapshot()
        let dictionary = DictionaryEngine(userDefaults: defaults)

        let matching = dictionary.apply(
            to: "Use post grass",
            snapshot: snapshot,
            activeApp: ActiveAppInfo(name: "Code", bundleIdentifier: "com.microsoft.VSCode"),
            language: "auto"
        )
        let other = dictionary.apply(
            to: "Use post grass",
            snapshot: snapshot,
            activeApp: ActiveAppInfo(name: "Notes", bundleIdentifier: "com.apple.Notes"),
            language: "auto"
        )

        XCTAssertEqual(matching.text, "Use Postgres")
        XCTAssertEqual(other.text, "Use post grass")
    }

    func testEvidenceOnlyCorrectionDoesNotChangeFutureDictation() async throws {
        let store = makeStore()
        _ = try await store.saveExplicitCorrection(ExplicitCorrectionWrite(
            memory: nil,
            evidence: CorrectionEvidenceDraft(
                originalText: "Is this ready.",
                correctedText: "Is this ready?"
            )
        ))
        let snapshot = try await store.memorySnapshot()

        let result = DictionaryEngine(userDefaults: defaults).apply(
            to: "Is this ready.",
            snapshot: snapshot,
            activeApp: nil,
            language: "auto"
        )

        XCTAssertEqual(result.text, "Is this ready.")
        XCTAssertTrue(snapshot.memories.isEmpty)
        let evidence = try await store.listEvidence()
        XCTAssertEqual(evidence.count, 1)
    }

    private func makeStore() -> LearningStore {
        LearningStore(databaseURL: tempRoot.appendingPathComponent("Learning.sqlite"))
    }
}
