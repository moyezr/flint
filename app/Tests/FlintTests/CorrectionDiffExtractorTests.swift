import XCTest
@testable import Flint

final class CorrectionDiffExtractorTests: XCTestCase {
    private let extractor = CorrectionDiffExtractor()

    func testExtractsSingleAndMultiWordSubstitutions() {
        XCTAssertEqual(
            extractor.extract(
                original: "Use post grass here.",
                corrected: "Use Postgres here."
            ),
            CorrectionProposal(heardForm: "post grass", preferredForm: "Postgres")
        )
        XCTAssertEqual(
            extractor.extract(
                original: "Open visual studio code now.",
                corrected: "Open VS Code now."
            ),
            CorrectionProposal(heardForm: "visual studio code", preferredForm: "VS Code")
        )
    }

    func testExtractsCasingAndPunctuationCorrections() {
        XCTAssertEqual(
            extractor.extract(original: "Use postgres.", corrected: "Use Postgres."),
            CorrectionProposal(heardForm: "postgres", preferredForm: "Postgres")
        )
        XCTAssertNil(extractor.extract(original: "Is this ready.", corrected: "Is this ready?"))
    }

    func testUsesUnicodeGraphemeBoundaries() {
        XCTAssertEqual(
            extractor.extract(original: "Send cafe now", corrected: "Send café now"),
            CorrectionProposal(heardForm: "cafe", preferredForm: "café")
        )
        XCTAssertEqual(
            extractor.extract(original: "Use 👩‍💻 icon", corrected: "Use 🧑‍💻 icon"),
            CorrectionProposal(heardForm: "👩‍💻", preferredForm: "🧑‍💻")
        )
    }

    func testRejectsInsertionDeletionUnchangedAndSeparatedChanges() {
        XCTAssertNil(extractor.extract(original: "cat", corrected: "catch"))
        XCTAssertNil(extractor.extract(original: "catch", corrected: "cat"))
        XCTAssertNil(extractor.extract(original: "same", corrected: "same"))
        XCTAssertNil(
            extractor.extract(
                original: "alpha stays omega",
                corrected: "ALPHA stays OMEGA"
            )
        )
    }

    func testEnforcesFiveWordAndEightyCharacterBounds() {
        XCTAssertNotNil(
            extractor.extract(
                original: "Keep this stable prefix one two three four five with stable suffix context",
                corrected: "Keep this stable prefix six seven eight nine ten with stable suffix context"
            )
        )
        XCTAssertNil(
            extractor.extract(
                original: "Keep this stable prefix one two three four five six with stable suffix context",
                corrected: "Keep this stable prefix seven eight nine ten eleven twelve with stable suffix context"
            )
        )

        let eighty = String(repeating: "a", count: 80)
        let eightyReplacement = String(repeating: "b", count: 80)
        let context = String(repeating: "context", count: 8)
        XCTAssertNotNil(
            extractor.extract(
                original: "\(context) \(eighty) \(context)",
                corrected: "\(context) \(eightyReplacement) \(context)"
            )
        )
        XCTAssertNil(
            extractor.extract(
                original: "\(context) \(eighty)a \(context)",
                corrected: "\(context) \(eightyReplacement)b \(context)"
            )
        )
    }

    func testRejectsRewriteThatConsumesMostOfLongSentence() {
        XCTAssertNil(
            extractor.extract(
                original: "Keep this prefix then replace nearly the entire long dictated sentence with different words at once",
                corrected: "Keep this prefix but rewrite almost all of the lengthy spoken sentence using completely new intent"
            )
        )
    }
}
