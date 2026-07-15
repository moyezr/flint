import XCTest
@testable import Flint

final class MemorySnapshotTests: XCTestCase {
    func testApplicationMappingOverridesGlobalMappingWithSameKey() {
        let global = makeMemory(preferred: "Flask", scope: .global)
        let application = makeMemory(
            preferred: "FLASK",
            scope: .application,
            scopeValue: "com.microsoft.VSCode"
        )
        let snapshot = MemorySnapshot(memories: [global, application])

        XCTAssertEqual(
            snapshot.vocabulary(language: "auto", applicationBundleID: "com.microsoft.VSCode").map(\.preferredForm),
            ["FLASK"]
        )
        XCTAssertEqual(
            snapshot.vocabulary(language: "auto", applicationBundleID: "com.apple.Notes").map(\.preferredForm),
            ["Flask"]
        )
    }

    func testExactLanguageOverridesAutoAndOtherLanguagesDoNotApply() {
        let automatic = makeMemory(preferred: "Color", language: "auto")
        let english = makeMemory(preferred: "Colour", language: "en")
        let french = makeMemory(heard: "couleur", preferred: "Couleur", language: "fr")
        let snapshot = MemorySnapshot(memories: [automatic, english, french])

        XCTAssertEqual(
            snapshot.vocabulary(language: "en", applicationBundleID: nil).map(\.preferredForm),
            ["Colour"]
        )
        XCTAssertFalse(
            snapshot.vocabulary(language: "en", applicationBundleID: nil).contains { $0.language == "fr" }
        )
    }

    func testLongerPhrasesSortBeforeShorterPhrases() {
        let short = makeMemory(heard: "next", preferred: "Next")
        let long = makeMemory(heard: "next dot js", preferred: "Next.js")
        let snapshot = MemorySnapshot(memories: [short, long])

        XCTAssertEqual(
            snapshot.vocabulary(language: "auto", applicationBundleID: nil).map(\.heardForm),
            ["next dot js", "next"]
        )
    }

    func testDisabledMemoriesAreExcluded() {
        let snapshot = MemorySnapshot(memories: [makeMemory(preferred: "Flask", status: .disabled)])
        XCTAssertTrue(snapshot.memories.isEmpty)
    }

    private func makeMemory(
        heard: String = "flask",
        preferred: String,
        scope: LearningScopeKind = .global,
        scopeValue: String = "",
        language: String = "auto",
        status: LearningMemoryStatus = .active
    ) -> LearningMemory {
        LearningMemory(
            id: UUID(),
            memoryType: .vocabulary,
            scopeKind: scope,
            scopeValue: scopeValue,
            language: language,
            heardForm: heard,
            heardKey: VocabularyNormalizer.key(for: heard),
            preferredForm: preferred,
            confidence: 1,
            evidenceCount: 1,
            usageCount: 0,
            status: status,
            origin: .seeded,
            createdAt: .distantPast,
            updatedAt: .distantPast,
            lastUsedAt: nil
        )
    }
}
