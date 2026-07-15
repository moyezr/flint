import XCTest
@testable import Flint

final class CorrectionMappingPolicyTests: XCTestCase {
    private let policy = CorrectionMappingPolicy()

    func testCommonPhraseToStyledEntityRequiresContext() {
        XCTAssertEqual(
            policy.safety(for: CorrectionProposal(heardForm: "next year", preferredForm: "Next.js")),
            .contextRequired
        )
    }

    func testSingleWordHomophoneRequiresContext() {
        XCTAssertEqual(
            policy.safety(for: CorrectionProposal(heardForm: "right", preferredForm: "write")),
            .contextRequired
        )
    }

    func testSpecificRareTermCanBeAppliedDirectly() {
        XCTAssertEqual(
            policy.safety(for: CorrectionProposal(heardForm: "post grass", preferredForm: "Postgres")),
            .direct
        )
        XCTAssertEqual(
            policy.safety(for: CorrectionProposal(heardForm: "next jay ess", preferredForm: "Next.js")),
            .direct
        )
    }
}
