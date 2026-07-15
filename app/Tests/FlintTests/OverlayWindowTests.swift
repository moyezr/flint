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

    func testOverlayMeterBarsClampAudioLevel() {
        XCTAssertEqual(presentation(for: .listening, audioLevel: -1).filledBars, 0)
        XCTAssertEqual(presentation(for: .listening, audioLevel: 0.02).filledBars, 0)
        XCTAssertEqual(presentation(for: .listening, audioLevel: 0.03).filledBars, 1)
        XCTAssertEqual(presentation(for: .listening, audioLevel: 0.5).filledBars, 5)
        XCTAssertEqual(presentation(for: .listening, audioLevel: 1.5).filledBars, 9)
    }

    func testOverlayUsesCompactOneSidedNotchIslandLayout() {
        XCTAssertEqual(OverlayLayout.size(for: .ready).width, 142)
        XCTAssertEqual(OverlayLayout.size(for: .listening).width, 190)
        XCTAssertEqual(OverlayLayout.size(for: .listening).height, 42)
        XCTAssertEqual(OverlayLayout.size(for: .preparingModel), OverlayLayout.activitySize)
        XCTAssertEqual(OverlayLayout.size(for: .inserted).width, 248)
        XCTAssertEqual(OverlayLayout.size(for: .error("Failed")).height, 42)
        XCTAssertEqual(OverlayLayout.size(for: .error("No speech detected.")).width, 190)
        XCTAssertEqual(OverlayLayout.meterBarCount, 9)
    }

    func testOverlayFrameAttachesToTopAndExtendsOnlyToTheRight() {
        let screen = CGRect(x: 0, y: 0, width: 1_512, height: 982)
        let readyFrame = OverlayLayout.frame(on: screen, for: .ready)
        let frame = OverlayLayout.frame(on: screen, for: .listening)

        XCTAssertEqual(readyFrame.midX, screen.midX)
        XCTAssertEqual(frame.minX, readyFrame.minX)
        XCTAssertGreaterThan(frame.maxX, readyFrame.maxX)
        XCTAssertEqual(frame.maxY, screen.maxY)
        XCTAssertEqual(frame.size, OverlayLayout.listeningSize)
    }

    func testErrorWidthGrowsOnlyAsMuchAsItsMessageNeeds() {
        let shortError = OverlayLayout.size(for: .error("No speech detected."))
        let longError = OverlayLayout.size(for: .error(
            "Model preparation failed. Press the dictation shortcut to retry."
        ))

        XCTAssertEqual(shortError.width, OverlayLayout.minimumErrorWidth)
        XCTAssertGreaterThan(longError.width, shortError.width)
        XCTAssertLessThanOrEqual(longError.width, OverlayLayout.maximumErrorWidth)
        XCTAssertEqual(longError.height, OverlayLayout.compactSize.height)
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
            XCTAssertEqual(OverlayLayout.size(for: state).height, OverlayLayout.compactSize.height)
        }
    }

    func testOverlayMeterBarsRepresentNonListeningStates() {
        XCTAssertEqual(presentation(for: .ready, audioLevel: 1).filledBars, 0)
        XCTAssertEqual(presentation(for: .preparingModel, audioLevel: 0).filledBars, 9)
        XCTAssertEqual(presentation(for: .processingLocally, audioLevel: 0).filledBars, 9)
        XCTAssertEqual(presentation(for: .inserting, audioLevel: 0).filledBars, 9)
        XCTAssertEqual(presentation(for: .error("Failed"), audioLevel: 1).filledBars, 3)
        XCTAssertEqual(presentation(for: .copiedToClipboard, audioLevel: 1).filledBars, 0)
        XCTAssertEqual(presentation(for: .cancelled, audioLevel: 1).filledBars, 0)
    }

    func testProcessingPulseMovesAcrossTheMeterWithoutChangingListeningBars() {
        let processing = presentation(for: .processingLocally)
        let earlyPulse = activeMeterBars(in: processing, phase: 5)
        let laterPulse = activeMeterBars(in: processing, phase: 11)

        XCTAssertTrue(processing.usesActivityPulse)
        XCTAssertFalse(presentation(for: .listening, audioLevel: 0.5).usesActivityPulse)
        XCTAssertFalse(earlyPulse.isEmpty)
        XCTAssertNotEqual(earlyPulse, laterPulse)
        XCTAssertLessThanOrEqual(earlyPulse.count, 4)
        XCTAssertLessThanOrEqual(laterPulse.count, 4)
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

    private func presentation(for state: OverlayState, audioLevel: Float = 0) -> OverlayPresentation {
        OverlayPresentation(
            state: state,
            audioLevel: audioLevel
        )
    }

    private func activeMeterBars(in presentation: OverlayPresentation, phase: Int) -> Set<Int> {
        Set((0..<OverlayLayout.meterBarCount).filter {
            presentation.isMeterBarActive($0, animationPhase: phase)
        })
    }
}
