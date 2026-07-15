import XCTest
@testable import Flint

@MainActor
final class QuickVocabularyModelTests: XCTestCase {
    func testDefaultsToRecentApplicationScope() {
        let entry = makeEntry(appName: "ChatGPT", bundleID: "com.openai.chat")
        let model = QuickVocabularyModel(recentDictation: entry, saveAction: { _ in .empty })

        XCTAssertEqual(model.scopeKind, .application)
        XCTAssertEqual(model.applicationName, "ChatGPT")
        XCTAssertTrue(model.canUseApplicationScope)
        XCTAssertFalse(model.canSave)
    }

    func testSavingPublishesSnapshotAndDismisses() async {
        let entry = makeEntry(appName: "Cursor", bundleID: "com.todesktop.cursor")
        let expectedSnapshot = MemorySnapshot(memories: [LearningMemory(
            id: UUID(),
            memoryType: .vocabulary,
            scopeKind: .application,
            scopeValue: "com.todesktop.cursor",
            language: "en",
            heardForm: "next jay ess",
            heardKey: "next jay ess",
            preferredForm: "Next.js",
            confidence: 1,
            evidenceCount: 1,
            usageCount: 0,
            status: .active,
            origin: .seeded,
            createdAt: Date(),
            updatedAt: Date(),
            lastUsedAt: nil
        )])
        var savedDraft: LearningMemoryDraft?
        var publishedSnapshot: MemorySnapshot?
        var savedCount = 0
        var dismissCount = 0
        let model = QuickVocabularyModel(
            recentDictation: entry,
            saveAction: { draft in
                savedDraft = draft
                return expectedSnapshot
            },
            onLearningChanged: { publishedSnapshot = $0 },
            onSaved: { savedCount += 1 }
        )
        model.onDismiss = { dismissCount += 1 }
        model.heardPhrase = "next jay ess"
        model.preferredPhrase = "Next.js"

        await model.save()

        XCTAssertEqual(savedDraft?.heardForm, "next jay ess")
        XCTAssertEqual(savedDraft?.preferredForm, "Next.js")
        XCTAssertEqual(savedDraft?.scopeKind, .application)
        XCTAssertEqual(savedDraft?.scopeValue, "com.todesktop.cursor")
        XCTAssertEqual(savedDraft?.language, "en")
        XCTAssertEqual(publishedSnapshot, expectedSnapshot)
        XCTAssertEqual(savedCount, 1)
        XCTAssertEqual(dismissCount, 1)
    }

    func testGlobalScopeClearsApplicationIdentifier() async {
        var savedDraft: LearningMemoryDraft?
        let model = QuickVocabularyModel(
            recentDictation: makeEntry(appName: "ChatGPT", bundleID: "com.openai.chat"),
            saveAction: { draft in
                savedDraft = draft
                return .empty
            }
        )
        model.scopeKind = .global
        model.heardPhrase = "post gress"
        model.preferredPhrase = "Postgres"

        await model.save()

        XCTAssertEqual(savedDraft?.scopeKind, .global)
        XCTAssertEqual(savedDraft?.scopeValue, "")
    }

    func testAmbiguousCommonPhraseCannotBecomeBlindVocabularyRule() {
        let model = QuickVocabularyModel(
            recentDictation: makeEntry(appName: "ChatGPT", bundleID: "com.openai.chat"),
            saveAction: { _ in .empty }
        )
        model.heardPhrase = "next year"
        model.preferredPhrase = "Next.js"

        XCTAssertEqual(model.mappingSafety, .contextRequired)
        XCTAssertFalse(model.canSave)
    }

    func testSaveFailureKeepsWindowOpenAndShowsError() async {
        var dismissCount = 0
        let model = QuickVocabularyModel(
            recentDictation: nil,
            saveAction: { _ in throw TestError.failed }
        )
        model.onDismiss = { dismissCount += 1 }
        model.heardPhrase = "live kit"
        model.preferredPhrase = "LiveKit"

        await model.save()

        XCTAssertEqual(model.errorMessage, "Unable to save vocabulary")
        XCTAssertEqual(dismissCount, 0)
    }

    private func makeEntry(appName: String?, bundleID: String?) -> RecentDictation {
        RecentDictation(
            rawText: "Use next year for the router.",
            insertedText: "Use next year for the router.",
            applicationName: appName,
            applicationBundleID: bundleID,
            language: "en",
            cleanupMode: .clean,
            deliveryResult: .inserted
        )
    }

    private enum TestError: LocalizedError {
        case failed

        var errorDescription: String? { "Unable to save vocabulary" }
    }
}
