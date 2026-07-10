import XCTest
@testable import Flint

final class OverlayWindowTests: XCTestCase {
    func testOverlayStateLabelsCoverRequiredStates() {
        XCTAssertEqual(OverlayState.ready.label, "READY")
        XCTAssertEqual(OverlayState.listening.label, "LISTENING")
        XCTAssertEqual(OverlayState.processingLocally.label, "PROCESSING")
        XCTAssertEqual(OverlayState.inserting.label, "INSERTING")
        XCTAssertEqual(OverlayState.copiedToClipboard.label, "COPIED TO CLIPBOARD")
        XCTAssertEqual(OverlayState.cancelled.label, "CANCELLED")
        XCTAssertEqual(OverlayState.error("No permission").label, "ERROR")
    }

    func testOverlayHintsMatchStateAndShortcutBehavior() {
        let pushToTalk = ShortcutSettings(option: .rightOption, behavior: .pushToTalk)
        let toggle = ShortcutSettings(option: .controlSpace, behavior: .toggle)

        XCTAssertEqual(OverlayState.ready.hint(settings: pushToTalk), "Hold Right Option to dictate")
        XCTAssertEqual(OverlayState.ready.hint(settings: toggle), "Press Control+Space to dictate")
        XCTAssertEqual(OverlayState.listening.hint(settings: pushToTalk), "Release to insert · Esc cancel")
        XCTAssertEqual(OverlayState.listening.hint(settings: toggle), "Press again to insert · Esc cancel")
        XCTAssertEqual(OverlayState.processingLocally.hint(settings: pushToTalk), "Transcribing")
        XCTAssertEqual(OverlayState.inserting.hint(settings: pushToTalk), "Pasting at cursor")
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
        XCTAssertEqual(presentation(for: .listening).accent, .active)
        XCTAssertEqual(presentation(for: .processingLocally).accent, .active)
        XCTAssertEqual(presentation(for: .inserting).accent, .active)
        XCTAssertEqual(presentation(for: .copiedToClipboard).accent, .inactive)
        XCTAssertEqual(presentation(for: .cancelled).accent, .inactive)
        XCTAssertEqual(presentation(for: .error("No permission")).accent, .error)
    }

    func testOverlayMeterBarsClampAudioLevel() {
        XCTAssertEqual(presentation(for: .listening, audioLevel: -1).filledBars, 0)
        XCTAssertEqual(presentation(for: .listening, audioLevel: 0.02).filledBars, 0)
        XCTAssertEqual(presentation(for: .listening, audioLevel: 0.03).filledBars, 1)
        XCTAssertEqual(presentation(for: .listening, audioLevel: 0.5).filledBars, 9)
        XCTAssertEqual(presentation(for: .listening, audioLevel: 1.5).filledBars, 18)
    }

    func testOverlayUsesCompactBottomLayout() {
        XCTAssertEqual(OverlayLayout.size(for: .listening).width, 230)
        XCTAssertEqual(OverlayLayout.size(for: .listening).height, 60)
        XCTAssertEqual(OverlayLayout.size(for: .error("Failed")).width, 230)
        XCTAssertEqual(OverlayLayout.size(for: .error("Failed")).height, 82)
        XCTAssertEqual(OverlayLayout.meterBarCount, 18)
    }

    func testOverlayMeterBarsRepresentNonListeningStates() {
        XCTAssertEqual(presentation(for: .ready, audioLevel: 1).filledBars, 0)
        XCTAssertEqual(presentation(for: .processingLocally, audioLevel: 0).filledBars, 14)
        XCTAssertEqual(presentation(for: .inserting, audioLevel: 0).filledBars, 14)
        XCTAssertEqual(presentation(for: .error("Failed"), audioLevel: 1).filledBars, 3)
        XCTAssertEqual(presentation(for: .copiedToClipboard, audioLevel: 1).filledBars, 0)
        XCTAssertEqual(presentation(for: .cancelled, audioLevel: 1).filledBars, 0)
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
        XCTAssertTrue(OverlayState.copiedToClipboard.shouldAutoHide)

        XCTAssertFalse(OverlayState.listening.shouldAutoHide)
        XCTAssertFalse(OverlayState.processingLocally.shouldAutoHide)
        XCTAssertFalse(OverlayState.inserting.shouldAutoHide)
        XCTAssertFalse(OverlayState.error("Failed").shouldAutoHide)
    }

    private func presentation(for state: OverlayState, audioLevel: Float = 0) -> OverlayPresentation {
        OverlayPresentation(
            state: state,
            modeLabel: "CLEAN",
            shortcutSettings: .default,
            audioLevel: audioLevel
        )
    }
}
