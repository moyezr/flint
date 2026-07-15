import XCTest
@testable import Flint

final class ModelPreparationLifecycleTests: XCTestCase {
    func testEarlyReadinessCheckDoesNotRestartActivePreparation() throws {
        var lifecycle = ModelPreparationLifecycle()
        let generation = try XCTUnwrap(lifecycle.begin(tier: .balanced))

        XCTAssertNil(lifecycle.begin(tier: .balanced))
        XCTAssertEqual(lifecycle.preparingTier, .balanced)
        XCTAssertTrue(lifecycle.complete(tier: .balanced, generation: generation))
        XCTAssertNil(lifecycle.preparingTier)
    }

    func testFailureCanBeRetriedWithoutRestartingApplication() throws {
        var lifecycle = ModelPreparationLifecycle()
        let firstGeneration = try XCTUnwrap(lifecycle.begin(tier: .balanced))
        XCTAssertTrue(lifecycle.fail(
            tier: .balanced,
            generation: firstGeneration,
            message: "Preparation timed out."
        ))
        XCTAssertEqual(lifecycle.error(for: .balanced), "Preparation timed out.")

        let retryGeneration = try XCTUnwrap(lifecycle.begin(tier: .balanced, force: true))
        XCTAssertGreaterThan(retryGeneration, firstGeneration)
        XCTAssertNil(lifecycle.error(for: .balanced))
        XCTAssertTrue(lifecycle.complete(tier: .balanced, generation: retryGeneration))
        XCTAssertEqual(lifecycle.state, .idle)
    }

    func testLateCompletionCannotOverrideNewerPreparation() throws {
        var lifecycle = ModelPreparationLifecycle()
        let oldGeneration = try XCTUnwrap(lifecycle.begin(tier: .balanced))
        let newGeneration = try XCTUnwrap(lifecycle.begin(tier: .accurate, force: true))

        XCTAssertFalse(lifecycle.complete(tier: .balanced, generation: oldGeneration))
        XCTAssertEqual(lifecycle.preparingTier, .accurate)
        XCTAssertTrue(lifecycle.complete(tier: .accurate, generation: newGeneration))
    }

    func testResetInvalidatesInFlightCompletion() throws {
        var lifecycle = ModelPreparationLifecycle()
        let generation = try XCTUnwrap(lifecycle.begin(tier: .fast))

        lifecycle.reset()

        XCTAssertEqual(lifecycle.state, .idle)
        XCTAssertFalse(lifecycle.complete(tier: .fast, generation: generation))
    }
}
