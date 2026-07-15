import XCTest
@testable import Flint

final class DictionaryEngineTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var engine: DictionaryEngine!

    override func setUp() {
        super.setUp()
        suiteName = "DictionaryEngineTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        engine = DictionaryEngine(userDefaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        engine = nil
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    func testDefaultReplacementsCoverCommonDeveloperTerms() {
        let transcript = "call the api with json from post gress in docker on kubernetes using type script and next js from git hub"

        XCTAssertEqual(
            engine.apply(to: transcript),
            "call the API with JSON from Postgres in Docker on Kubernetes using TypeScript and Next.js from GitHub"
        )
    }

    func testCustomReplacementsPersistInUserDefaultsSuite() {
        let replacement = engine.addReplacement(heardPhrase: "live kit", preferredReplacement: "LiveKit", category: "product")

        let reloadedEngine = DictionaryEngine(userDefaults: defaults)

        XCTAssertEqual(reloadedEngine.listCustomReplacements(), [replacement])
        XCTAssertEqual(reloadedEngine.apply(to: "ship live kit support"), "ship LiveKit support")
    }

    func testRemoveCustomReplacement() {
        let replacement = engine.addReplacement(heardPhrase: "live kit", preferredReplacement: "LiveKit")

        engine.removeReplacement(id: replacement.id)

        XCTAssertTrue(engine.listCustomReplacements().isEmpty)
        XCTAssertEqual(engine.apply(to: "ship live kit support"), "ship live kit support")
    }

    func testPhraseBoundariesDoNotRewriteInsideLargerWords() {
        engine.addReplacement(heardPhrase: "api", preferredReplacement: "API")

        XCTAssertEqual(
            engine.apply(to: "api capillary graphqlapi api-client"),
            "API capillary graphqlapi API-client"
        )
    }

    func testPhraseMatchingIsCaseInsensitiveAndAllowsWhitespaceBetweenWords() {
        engine.addReplacement(heardPhrase: "live kit", preferredReplacement: "LiveKit")

        XCTAssertEqual(
            engine.apply(to: "LIVE   KIT should work"),
            "LiveKit should work"
        )
    }

    func testUsageCountIncrementsWhenCustomReplacementIsApplied() {
        let replacement = engine.addReplacement(heardPhrase: "live kit", preferredReplacement: "LiveKit")

        XCTAssertEqual(engine.apply(to: "live kit and live kit"), "LiveKit and LiveKit")

        XCTAssertEqual(engine.listCustomReplacements().first { $0.id == replacement.id }?.usageCount, 2)
    }

    func testUsageCountDoesNotIncrementWhenCustomReplacementDoesNotMatch() {
        let replacement = engine.addReplacement(heardPhrase: "live kit", preferredReplacement: "LiveKit")

        XCTAssertEqual(engine.apply(to: "nothing to replace"), "nothing to replace")

        XCTAssertEqual(engine.listCustomReplacements().first { $0.id == replacement.id }?.usageCount, 0)
    }

    func testRemoveAllCustomReplacementsClearsOnlyCustomEntries() {
        engine.addReplacement(heardPhrase: "live kit", preferredReplacement: "LiveKit")

        engine.removeAllCustomReplacements()

        XCTAssertTrue(engine.listCustomReplacements().isEmpty)
        XCTAssertEqual(engine.apply(to: "api and live kit"), "API and live kit")
    }

    func testSnapshotApplicationReturnsMatchesWithoutWritingUserDefaults() {
        let memory = makeMemory(heard: "post grass", preferred: "Postgres")
        let result = engine.apply(
            to: "Use post grass and post grass",
            snapshot: MemorySnapshot(memories: [memory]),
            activeApp: nil,
            language: "auto"
        )

        XCTAssertEqual(result.text, "Use Postgres and Postgres")
        XCTAssertEqual(result.matchedMemoryCounts, [memory.id: 2])
        XCTAssertTrue(engine.listCustomReplacements().isEmpty)
    }

    func testApplicationSnapshotMappingOverridesGlobal() {
        let global = makeMemory(heard: "flask", preferred: "Flask")
        let application = makeMemory(
            heard: "flask",
            preferred: "FLASK",
            scope: .application,
            scopeValue: "com.microsoft.VSCode"
        )
        let snapshot = MemorySnapshot(memories: [global, application])

        XCTAssertEqual(
            engine.apply(
                to: "use flask",
                snapshot: snapshot,
                activeApp: ActiveAppInfo(name: "Code", bundleIdentifier: "com.microsoft.VSCode"),
                language: "auto"
            ).text,
            "use FLASK"
        )
        XCTAssertEqual(
            engine.apply(
                to: "use flask",
                snapshot: snapshot,
                activeApp: ActiveAppInfo(name: "Notes", bundleIdentifier: "com.apple.Notes"),
                language: "auto"
            ).text,
            "use Flask"
        )
    }

    func testUserSnapshotMappingCanOverrideBuiltInMapping() {
        let memory = makeMemory(heard: "api", preferred: "api")
        let result = engine.apply(
            to: "API design",
            snapshot: MemorySnapshot(memories: [memory]),
            activeApp: nil,
            language: "auto"
        )

        XCTAssertEqual(result.text, "api design")
        XCTAssertEqual(result.matchedMemoryCounts, [memory.id: 1])
    }

    func testEmptySnapshotPreservesBuiltInDictionary() {
        let result = engine.apply(
            to: "next dot js uses json",
            snapshot: .empty,
            activeApp: nil,
            language: "auto"
        )

        XCTAssertEqual(result.text, "Next.js uses JSON")
        XCTAssertTrue(result.matchedMemoryCounts.isEmpty)
    }

    func testSnapshotWithOneThousandIndexedMappingsAppliesCorrectEntry() {
        let memories = (0..<1_000).map { index in
            makeMemory(heard: "term \(index)", preferred: "Term\(index)")
        }
        let snapshot = MemorySnapshot(memories: memories)

        let result = engine.apply(
            to: "Use term 999 in this sentence",
            snapshot: snapshot,
            activeApp: nil,
            language: "auto"
        )

        XCTAssertEqual(result.text, "Use Term999 in this sentence")
        XCTAssertEqual(result.matchedMemoryCounts.values.reduce(0, +), 1)
    }

    private func makeMemory(
        heard: String,
        preferred: String,
        scope: LearningScopeKind = .global,
        scopeValue: String = ""
    ) -> LearningMemory {
        LearningMemory(
            id: UUID(),
            memoryType: .vocabulary,
            scopeKind: scope,
            scopeValue: scopeValue,
            language: "auto",
            heardForm: heard,
            heardKey: VocabularyNormalizer.key(for: heard),
            preferredForm: preferred,
            confidence: 1,
            evidenceCount: 1,
            usageCount: 0,
            status: .active,
            origin: .seeded,
            createdAt: .distantPast,
            updatedAt: .distantPast,
            lastUsedAt: nil
        )
    }
}
