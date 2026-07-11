import XCTest
@testable import Flint

final class AudioRecorderTests: XCTestCase {
    func testDecibelNormalizationClampsQuietValuesToZero() {
        XCTAssertEqual(AudioLevelNormalizer.normalizedLevel(fromDecibels: -160), 0)
        XCTAssertEqual(AudioLevelNormalizer.normalizedLevel(fromDecibels: -60), 0)
    }

    func testDecibelNormalizationMapsConfiguredRange() {
        XCTAssertEqual(AudioLevelNormalizer.normalizedLevel(fromDecibels: -30), 0.5, accuracy: 0.001)
        XCTAssertEqual(AudioLevelNormalizer.normalizedLevel(fromDecibels: 0), 1)
    }

    func testDecibelNormalizationClampsLoudValuesToOne() {
        XCTAssertEqual(AudioLevelNormalizer.normalizedLevel(fromDecibels: 6), 1)
    }

    func testDecibelNormalizationHandlesInvalidValues() {
        XCTAssertEqual(AudioLevelNormalizer.normalizedLevel(fromDecibels: .nan), 0)
        XCTAssertEqual(AudioLevelNormalizer.normalizedLevel(fromDecibels: -.infinity), 0)
        XCTAssertEqual(AudioLevelNormalizer.normalizedLevel(fromDecibels: .infinity), 1)
    }
}
