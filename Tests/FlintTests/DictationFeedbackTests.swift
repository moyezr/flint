import XCTest
@testable import Flint

@MainActor
final class DictationFeedbackTests: XCTestCase {
    func testStartFeedbackAlwaysUsesHapticAndRespectsSoundPreference() {
        var sounds: [DictationFeedbackSound] = []
        var haptics: [DictationHaptic] = []
        let feedback = DictationFeedback(
            soundPlayer: { sounds.append($0) },
            hapticPerformer: { haptics.append($0) },
            errorBeep: { XCTFail("Start feedback should not beep.") }
        )

        feedback.perform(.started, settings: .default)

        var soundEnabledSettings = AppSettings.default
        soundEnabledSettings.playStartSound = true
        feedback.perform(.started, settings: soundEnabledSettings)

        XCTAssertEqual(haptics, [.started, .started])
        XCTAssertEqual(sounds, [.started])
    }

    func testStopSoundAndCompletionHapticHaveDistinctFeedback() {
        var sounds: [DictationFeedbackSound] = []
        var haptics: [DictationHaptic] = []
        let feedback = DictationFeedback(
            soundPlayer: { sounds.append($0) },
            hapticPerformer: { haptics.append($0) },
            errorBeep: { XCTFail("Successful feedback should not beep.") }
        )
        var settings = AppSettings.default
        settings.playStopSound = true

        feedback.perform(.stopped, settings: settings)
        feedback.perform(.inserted, settings: settings)

        XCTAssertEqual(sounds, [.stopped])
        XCTAssertEqual(haptics, [.completed])
    }

    func testCancellationAndFailureUseDistinctHaptics() {
        var haptics: [DictationHaptic] = []
        var beepCount = 0
        let feedback = DictationFeedback(
            soundPlayer: { _ in XCTFail("Cancellation and failure should not play transition sounds.") },
            hapticPerformer: { haptics.append($0) },
            errorBeep: { beepCount += 1 }
        )

        feedback.perform(.cancelled, settings: .default)
        feedback.perform(.failed, settings: .default)

        XCTAssertEqual(haptics, [.cancelled, .failed])
        XCTAssertEqual(beepCount, 1)
    }
}
