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
}
