import XCTest
@testable import Flint

final class LearningMetricsTests: XCTestCase {
    func testCountersPersistWithoutUserContentAndCanBeReset() async {
        let suite = "FlintTests.LearningMetrics.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        let metrics = LearningMetrics(defaults: defaults)

        await metrics.increment(.completedUsableDictations)
        await metrics.increment(.activeMemoriesApplied, by: 3)

        let reloaded = LearningMetrics(defaults: defaults)
        let snapshot = await reloaded.snapshot()
        XCTAssertEqual(snapshot[.completedUsableDictations], 1)
        XCTAssertEqual(snapshot[.activeMemoriesApplied], 3)
        XCTAssertTrue(snapshot.plainTextSummary.contains("fix_saves: 0"))
        XCTAssertFalse(snapshot.plainTextSummary.contains("dictated text"))

        await reloaded.reset()
        let resetSnapshot = await reloaded.snapshot()
        XCTAssertEqual(resetSnapshot, .emptyWithZeroes)
    }
}

private extension LearningMetricsSnapshot {
    static var emptyWithZeroes: LearningMetricsSnapshot {
        LearningMetricsSnapshot(counts: Dictionary(
            uniqueKeysWithValues: LearningMetric.allCases.map { ($0, 0) }
        ))
    }
}
