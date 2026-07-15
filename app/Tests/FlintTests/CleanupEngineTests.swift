import XCTest
@testable import Flint

final class CleanupEngineTests: XCTestCase {
    private let engine = CleanupEngine()

    func testVerbatimOnlyTrimsOuterWhitespace() {
        let transcript = " \n  um, hello   world  \n "

        XCTAssertEqual(
            engine.clean(transcript, mode: .verbatim),
            "um, hello   world"
        )
    }

    func testFormattingPreferencesCanPreserveFillersAndOmitAddedPunctuation() {
        let preferences = CleanupPreferences(
            removeFillerWords: false,
            addTerminalPunctuation: false
        )

        XCTAssertEqual(
            CleanupEngine().clean(" um this is useful ", mode: .clean, preferences: preferences),
            "Um this is useful"
        )
    }

    func testFormattingPreferencesApplyToDerivedModesButNotVerbatim() {
        let preferences = CleanupPreferences(
            removeFillerWords: false,
            addTerminalPunctuation: false
        )

        XCTAssertEqual(
            CleanupEngine().clean("um please review this", mode: .polished, preferences: preferences),
            "Um please review this"
        )
        XCTAssertEqual(
            CleanupEngine().clean("  um please review this  ", mode: .verbatim, preferences: preferences),
            "um please review this"
        )
    }

    func testCleanRemovesFillersWhitespaceAndPunctuationSpacing() {
        let transcript = "  um, hello   world ,  this is uh a test  "

        XCTAssertEqual(
            engine.clean(transcript, mode: .clean),
            "Hello world, this is a test."
        )
    }

    func testCleanIsDefaultMode() {
        XCTAssertEqual(
            engine.clean("  um hello  "),
            "Hello."
        )
    }

    func testCleanCapitalizesSentenceStarts() {
        XCTAssertEqual(
            engine.clean("hello there. this is flint", mode: .clean),
            "Hello there. This is flint."
        )
    }

    func testCleanDoesNotRewriteSemanticLikeOrYouKnow() {
        XCTAssertEqual(
            engine.clean("i like Swift and do you know Rust", mode: .clean),
            "I like Swift and do you know Rust."
        )
    }

    func testCleanKeepsSemanticYouKnowAtSentenceEnd() {
        XCTAssertEqual(
            engine.clean("do you know", mode: .clean),
            "Do you know."
        )
    }

    func testCleanRemovesDelimitedTrailingYouKnowAsFiller() {
        XCTAssertEqual(
            engine.clean("we can ship this, you know", mode: .clean),
            "We can ship this."
        )
    }

    func testCleanKeepsSemanticLikeAtSentenceStart() {
        XCTAssertEqual(
            engine.clean("like Swift when writing mac apps", mode: .clean),
            "Like Swift when writing mac apps."
        )
    }

    func testCleanRemovesDelimitedStartingLikeAsFiller() {
        XCTAssertEqual(
            engine.clean("like, are we ready?", mode: .clean),
            "Are we ready?"
        )
    }

    func testCleanDoesNotAddPunctuationWhenAlreadyPresent() {
        XCTAssertEqual(
            engine.clean("are we ready?", mode: .clean),
            "Are we ready?"
        )
    }

    func testPolishedAppliesLightCasingAndQuestionPunctuation() {
        XCTAssertEqual(
            engine.clean("can i ship this now", mode: .polished),
            "Can I ship this now?"
        )
    }

    func testPromptNormalizesLeadingInstructionWithoutSemanticRewrite() {
        XCTAssertEqual(
            engine.clean("can you please update the SwiftUI view to use JSON", mode: .prompt),
            "Please update the SwiftUI view to use JSON."
        )
    }

    func testPromptRemovesAssistantAddress() {
        XCTAssertEqual(
            engine.clean("Claude, explain this TypeScript error", mode: .prompt),
            "Explain this TypeScript error."
        )
    }

    func testMessageKeepsChatStyleConcise() {
        XCTAssertEqual(
            engine.clean("hey, could you please review this when you have a chance", mode: .message),
            "Could you review this when you have a chance?"
        )
    }

    func testEmailFormatsBlockOnlyWhenEmailCuesExist() {
        XCTAssertEqual(
            engine.clean("hi Sam, please review the draft thanks", mode: .email),
            "Hi Sam,\n\nPlease review the draft.\n\nThanks"
        )
    }

    func testEmailFallsBackToPolishedTextWithoutEmailCues() {
        XCTAssertEqual(
            engine.clean("can i send this now", mode: .email),
            "Can I send this now?"
        )
    }

    func testCleanupModeSelectionStoreDefaultsToCleanForMissingOrUnknownValue() {
        let defaults = UserDefaults(suiteName: "CleanupModeSelectionStoreTests.missing")!
        defaults.removePersistentDomain(forName: "CleanupModeSelectionStoreTests.missing")
        let store = CleanupModeSelectionStore(defaults: defaults, key: "mode")

        XCTAssertEqual(store.load(), .clean)

        defaults.set("unknown", forKey: "mode")
        XCTAssertEqual(store.load(), .clean)
    }

    func testCleanupModeSelectionStorePersistsSelectedMode() {
        let defaults = UserDefaults(suiteName: "CleanupModeSelectionStoreTests.persisted")!
        defaults.removePersistentDomain(forName: "CleanupModeSelectionStoreTests.persisted")
        let store = CleanupModeSelectionStore(defaults: defaults, key: "mode")

        store.save(.message)

        XCTAssertEqual(store.load(), .message)
    }
}
