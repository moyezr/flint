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
}
