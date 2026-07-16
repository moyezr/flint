import XCTest
@testable import Flint

final class OverlayWindowTests: XCTestCase {
    func testOverlayStateLabelsCoverRequiredStates() {
        XCTAssertEqual(OverlayState.ready.label, "READY")
        XCTAssertEqual(OverlayState.preparingModel.label, "PREPARING MODEL")
        XCTAssertEqual(OverlayState.listening.label, "LISTENING")
        XCTAssertEqual(OverlayState.processingLocally.label, "PROCESSING")
        XCTAssertEqual(OverlayState.inserting.label, "INSERTING")
        XCTAssertEqual(OverlayState.inserted.label, "INSERTED")
        XCTAssertEqual(OverlayState.copiedToClipboard.label, "COPIED")
        XCTAssertEqual(OverlayState.cancelled.label, "CANCELLED")
        XCTAssertEqual(OverlayState.error("No permission").label, "ERROR")
    }

    func testOverlayHintsMatchStateAndShortcutBehavior() {
        let pushToTalk = ShortcutSettings(option: .rightOption, behavior: .pushToTalk)
        let toggle = ShortcutSettings(option: .controlSpace, behavior: .toggle)

        XCTAssertEqual(OverlayState.ready.hint(settings: pushToTalk), "Hold Right Option to dictate")
        XCTAssertEqual(OverlayState.preparingModel.hint(settings: pushToTalk), "First launch can take a moment")
        XCTAssertEqual(OverlayState.ready.hint(settings: toggle), "Press Control+Space to dictate")
        XCTAssertEqual(OverlayState.listening.hint(settings: pushToTalk), "Release to insert · Esc cancel")
        XCTAssertEqual(OverlayState.listening.hint(settings: toggle), "Press again to insert · Esc cancel")
        XCTAssertEqual(OverlayState.processingLocally.hint(settings: pushToTalk), "Turning speech into text")
        XCTAssertEqual(OverlayState.inserting.hint(settings: pushToTalk), "Pasting at cursor")
        XCTAssertEqual(OverlayState.inserted.hint(settings: pushToTalk), "Inserted at cursor")
        XCTAssertEqual(OverlayState.copiedToClipboard.hint(settings: pushToTalk), "Paste manually if needed")
        XCTAssertEqual(OverlayState.cancelled.hint(settings: pushToTalk), "Recording discarded")
        XCTAssertEqual(OverlayState.error("Microphone permission is required.").hint(settings: pushToTalk), "Microphone permission is required.")
    }

    func testProcessingFeedbackDoesNotExposeLocalWording() {
        let processing = OverlayState.processingLocally
        let visibleText = [processing.label, processing.hint(settings: .default)].joined(separator: " ").lowercased()

        XCTAssertFalse(visibleText.contains("local"))
        XCTAssertFalse(visibleText.contains("local transcription"))
    }

    func testOverlayPresentationAccentRoles() {
        XCTAssertEqual(presentation(for: .ready).accent, .inactive)
        XCTAssertEqual(presentation(for: .preparingModel).accent, .active)
        XCTAssertEqual(presentation(for: .listening).accent, .active)
        XCTAssertEqual(presentation(for: .processingLocally).accent, .active)
        XCTAssertEqual(presentation(for: .inserting).accent, .active)
        XCTAssertEqual(presentation(for: .inserted).accent, .success)
        XCTAssertEqual(presentation(for: .copiedToClipboard).accent, .success)
        XCTAssertEqual(presentation(for: .cancelled).accent, .inactive)
        XCTAssertEqual(presentation(for: .error("No permission")).accent, .error)
    }

    func testOverlayUsesCompactCenteredPillWithoutHardwareNotch() {
        XCTAssertEqual(OverlayLayout.size(for: .ready).width, 142)
        XCTAssertEqual(OverlayLayout.size(for: .listening).width, 100)
        XCTAssertEqual(OverlayLayout.size(for: .listening).height, 42)
        XCTAssertEqual(OverlayLayout.size(for: .preparingModel), OverlayLayout.activitySize)
        XCTAssertEqual(OverlayLayout.size(for: .processingLocally).width, 80)
        XCTAssertEqual(OverlayLayout.size(for: .inserted).width, 178)
        XCTAssertEqual(OverlayLayout.size(for: .error("Failed")).height, 42)
        XCTAssertEqual(OverlayLayout.size(for: .error("No speech detected.")).width, 168)
        XCTAssertLessThan(OverlayLayout.spinnerWingWidth, OverlayLayout.waveformWingWidth)
    }

    func testWindowMotionSlidesIntoTopEdgeWithoutChangingSize() {
        let visibleFrame = CGRect(x: 400, y: 900, width: 178, height: 42)
        let hiddenFrame = OverlayMotion.hiddenFrame(from: visibleFrame)

        XCTAssertEqual(hiddenFrame.origin.x, visibleFrame.origin.x)
        XCTAssertEqual(hiddenFrame.origin.y, visibleFrame.origin.y + OverlayMotion.verticalOffset)
        XCTAssertEqual(hiddenFrame.size, visibleFrame.size)
        XCTAssertGreaterThan(OverlayMotion.appearanceDuration, 0)
        XCTAssertGreaterThan(OverlayMotion.disappearanceDuration, 0)
    }

    func testAudioWaveformBoostsQuietSpeechAndVariesLineHeights() {
        var smoother = AudioWaveformSmoother()

        smoother.update(averageLevel: 0.1, peakLevel: 0.18)

        XCTAssertEqual(smoother.samples.count, AudioWaveformSmoother.sampleCount)
        XCTAssertGreaterThan(smoother.level, 0.1)
        XCTAssertGreaterThan(distinctLineHeightCount(smoother.samples), 2)
    }

    func testAudioWaveformKeepsMovingDuringSustainedSpeech() {
        var smoother = AudioWaveformSmoother()
        smoother.update(averageLevel: 0.4, peakLevel: 0.62)
        let firstFrame = smoother.samples

        smoother.update(averageLevel: 0.4, peakLevel: 0.62)

        XCTAssertNotEqual(smoother.samples, firstFrame)
        XCTAssertGreaterThan(distinctLineHeightCount(smoother.samples), 2)
    }

    func testAudioWaveformHeightTracksLoudness() {
        var quiet = AudioWaveformSmoother()
        var loud = AudioWaveformSmoother()

        quiet.update(averageLevel: 0.08, peakLevel: 0.12)
        loud.update(averageLevel: 0.65, peakLevel: 0.9)

        XCTAssertGreaterThan(loud.samples.reduce(0, +), quiet.samples.reduce(0, +))
    }

    func testAudioWaveformReleasesSmoothlyIntoSilence() {
        var smoother = AudioWaveformSmoother()
        smoother.update(averageLevel: 0.7, peakLevel: 0.9)
        let activeLevel = smoother.level

        smoother.update(averageLevel: 0, peakLevel: 0)

        XCTAssertLessThan(smoother.level, activeLevel)
        XCTAssertGreaterThan(smoother.level, 0)
    }

    func testAudioWaveformCanBeResetBetweenRecordings() {
        var smoother = AudioWaveformSmoother()
        smoother.update(averageLevel: 0.7, peakLevel: 0.9)

        smoother.reset()

        XCTAssertEqual(smoother.level, 0)
        XCTAssertTrue(smoother.samples.allSatisfy { $0 == 0 })
    }

    func testOverlayFrameCentersCompactPillWhenScreenHasNoNotch() {
        let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let readyFrame = OverlayLayout.frame(on: screen, for: .ready)
        let frame = OverlayLayout.frame(on: screen, for: .listening)

        XCTAssertEqual(readyFrame.midX, screen.midX)
        XCTAssertEqual(frame.midX, screen.midX)
        XCTAssertEqual(frame.maxY, screen.maxY)
        XCTAssertEqual(frame.size, OverlayLayout.listeningSize)
    }

    func testScreenGeometryUsesMacOSNotchAreasInsteadOfAssumingCenter() {
        let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let leftArea = CGRect(x: 0, y: 944, width: 666, height: 38)
        let rightArea = CGRect(x: 846, y: 944, width: 666, height: 38)
        let geometry = OverlayLayout.screenGeometry(
            screenFrame: screen,
            auxiliaryTopLeftArea: leftArea,
            auxiliaryTopRightArea: rightArea
        )

        XCTAssertEqual(geometry.notchMinX, 666)
        XCTAssertEqual(geometry.notchWidth, 180)
        XCTAssertEqual(geometry.notchMaxX, 846)
        XCTAssertTrue(geometry.hasHardwareNotch)

        let frame = OverlayLayout.frame(on: screen, for: .listening, geometry: geometry)
        XCTAssertEqual(frame.minX, geometry.notchMinX - OverlayLayout.statusWingWidth)
        XCTAssertEqual(frame.maxX, geometry.notchMaxX + OverlayLayout.waveformWingWidth)
        XCTAssertEqual(frame.width, 180 + OverlayLayout.statusWingWidth + OverlayLayout.waveformWingWidth)
        XCTAssertEqual(frame.maxY, screen.maxY)
    }

    func testScreenGeometryFallsBackToCenteredVirtualNotch() {
        let screen = CGRect(x: 300, y: 20, width: 1_200, height: 800)
        let geometry = OverlayLayout.screenGeometry(
            screenFrame: screen,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )

        XCTAssertEqual(geometry.notchWidth, 0)
        XCTAssertEqual(geometry.notchMinX, screen.midX)
        XCTAssertFalse(geometry.hasHardwareNotch)
    }

    func testErrorWidthGrowsOnlyAsMuchAsItsMessageNeeds() {
        let shortError = OverlayLayout.errorMessageWingWidth(for: "No speech detected.")
        let longError = OverlayLayout.errorMessageWingWidth(for:
            "Model preparation failed. Press the dictation shortcut to retry."
        )

        XCTAssertEqual(shortError, OverlayLayout.minimumErrorMessageWingWidth)
        XCTAssertGreaterThan(longError, shortError)
        XCTAssertLessThanOrEqual(longError, OverlayLayout.maximumErrorMessageWingWidth)
    }

    func testEveryIslandStateKeepsTheCompactHeight() {
        let states: [OverlayState] = [
            .ready,
            .preparingModel,
            .listening,
            .processingLocally,
            .inserting,
            .inserted,
            .copiedToClipboard,
            .cancelled,
            .error("No speech detected.")
        ]

        for state in states {
            XCTAssertEqual(OverlayLayout.size(for: state).height, OverlayLayout.islandHeight)
        }
    }

    func testAutoHideCoordinatorOnlyAcceptsCurrentGeneration() {
        var coordinator = OverlayAutoHideCoordinator()

        let readyPlan = coordinator.show(.ready)
        XCTAssertTrue(readyPlan.shouldAutoHide)
        XCTAssertTrue(coordinator.acceptsAutoHide(generation: readyPlan.generation))

        let listeningPlan = coordinator.show(.listening)
        XCTAssertFalse(listeningPlan.shouldAutoHide)
        XCTAssertFalse(coordinator.acceptsAutoHide(generation: readyPlan.generation))
        XCTAssertTrue(coordinator.acceptsAutoHide(generation: listeningPlan.generation))
    }

    func testOnlyTransientStatesScheduleAutoHide() {
        XCTAssertTrue(OverlayState.ready.shouldAutoHide)
        XCTAssertTrue(OverlayState.cancelled.shouldAutoHide)
        XCTAssertTrue(OverlayState.inserted.shouldAutoHide)
        XCTAssertTrue(OverlayState.copiedToClipboard.shouldAutoHide)

        XCTAssertFalse(OverlayState.listening.shouldAutoHide)
        XCTAssertFalse(OverlayState.preparingModel.shouldAutoHide)
        XCTAssertFalse(OverlayState.processingLocally.shouldAutoHide)
        XCTAssertFalse(OverlayState.inserting.shouldAutoHide)
        XCTAssertFalse(OverlayState.error("Failed").shouldAutoHide)
    }

    private func presentation(for state: OverlayState) -> OverlayPresentation {
        OverlayPresentation(state: state)
    }

    private func distinctLineHeightCount(_ samples: [Float]) -> Int {
        Set(samples.map { Int(($0 * 1_000).rounded()) }).count
    }
}
