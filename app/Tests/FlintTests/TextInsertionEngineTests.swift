import ApplicationServices
import XCTest
@testable import Flint

@MainActor
final class TextInsertionEngineTests: XCTestCase {
    func testAccessibilityInsertionRequiresAVisibleValueChange() {
        XCTAssertFalse(TextInsertionEngine.didAccessibilityValueChange(from: "before", to: "before"))
        XCTAssertTrue(TextInsertionEngine.didAccessibilityValueChange(from: "before", to: "after"))
    }

    func testAccessibilityValueReplacementUsesSelectedRange() {
        XCTAssertEqual(
            TextInsertionEngine.replacingSelectedText(
                in: "hello world",
                selectedRange: NSRange(location: 6, length: 5),
                with: "Flint"
            ),
            "hello Flint"
        )
    }

    func testAccessibilityValueReplacementRejectsInvalidRange() {
        XCTAssertNil(
            TextInsertionEngine.replacingSelectedText(
                in: "hello",
                selectedRange: NSRange(location: 4, length: 3),
                with: "Flint"
            )
        )
    }

    func testComposerPlaceholderValueIsReplacedInsteadOfAppended() {
        XCTAssertTrue(
            TextInsertionEngine.shouldReplacePlaceholderValue(
                "Write a message...",
                placeholderValue: nil
            )
        )
        XCTAssertTrue(
            TextInsertionEngine.shouldReplacePlaceholderValue(
                "Message Claude",
                placeholderValue: "Message Claude"
            )
        )
        XCTAssertFalse(
            TextInsertionEngine.shouldReplacePlaceholderValue(
                "Write a message about launch planning.",
                placeholderValue: nil
            )
        )
        XCTAssertFalse(
            TextInsertionEngine.shouldReplacePlaceholderValue(
                "Actual dictated text",
                placeholderValue: "Write a message..."
            )
        )
    }

    func testRecordingStartInsertsIntoCapturedTargetWithoutQueryingCurrentFocus() async {
        let capturedTarget = TextInsertionTarget(element: AXUIElementCreateSystemWide())
        var insertedText: String?
        var insertAttempts = 0

        let engine = TextInsertionEngine(
            focusedTargetProvider: {
                XCTFail("Focused target should not be queried when captured insertion succeeds.")
                return nil
            },
            accessibilityInserter: { _, text in
                insertAttempts += 1
                insertedText = text
                return true
            },
            pasteFallback: { _ in
                XCTFail("Paste fallback should not run when captured insertion succeeds.")
                return false
            },
            copyToClipboard: { _ in
                XCTFail("Copy fallback should not run when captured insertion succeeds.")
            }
        )

        let result = await engine.insert("dictated text", preferredTarget: capturedTarget)

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(insertAttempts, 1)
        XCTAssertEqual(insertedText, "dictated text")
    }

    func testRecordingStartUsesCurrentFocusedFieldWhenCapturedTargetRejectsInsertion() async {
        let capturedTarget = TextInsertionTarget(element: AXUIElementCreateSystemWide())
        let focusedTarget = TextInsertionTarget(element: AXUIElementCreateApplication(getpid()))
        var events: [String] = []

        let engine = TextInsertionEngine(
            focusedTargetProvider: {
                events.append("focusedTarget")
                return focusedTarget
            },
            accessibilityInserter: { target, _ in
                events.append("accessibilityInsert")
                return target.element === focusedTarget.element
            },
            pasteFallback: { text in
                XCTFail("Paste fallback should not run when current focused insertion succeeds: \(text)")
                return false
            },
            copyToClipboard: { _ in
                XCTFail("Copy fallback should not run when current focused insertion succeeds.")
            }
        )

        let result = await engine.insert("dictated text", preferredTarget: capturedTarget)

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(events, ["accessibilityInsert", "focusedTarget", "accessibilityInsert"])
    }

    func testRecordingStartFallsBackToPasteWhenAccessibilityObjectsDoNotMatch() async {
        let capturedTarget = TextInsertionTarget(element: AXUIElementCreateSystemWide())
        let focusedTarget = TextInsertionTarget(element: AXUIElementCreateApplication(getpid()))
        var events: [String] = []

        let engine = TextInsertionEngine(
            focusedTargetProvider: {
                events.append("focusedTarget")
                return focusedTarget
            },
            accessibilityInserter: { _, _ in
                events.append("accessibilityInsert")
                return false
            },
            pasteFallback: { text in
                events.append("paste:\(text)")
                return true
            },
            copyToClipboard: { _ in
                XCTFail("Copy fallback should not run when paste succeeds.")
            }
        )

        let result = await engine.insert("dictated text", preferredTarget: capturedTarget)

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(events, ["accessibilityInsert", "focusedTarget", "accessibilityInsert", "paste:dictated text"])
    }

    func testRecordingStartFallsBackToPasteWhenCurrentFocusIsMissing() async {
        let capturedTarget = TextInsertionTarget(element: AXUIElementCreateSystemWide())
        var events: [String] = []

        let engine = TextInsertionEngine(
            focusedTargetProvider: {
                events.append("focusedTarget")
                return nil
            },
            accessibilityInserter: { _, _ in
                events.append("accessibilityInsert")
                return false
            },
            pasteFallback: { text in
                events.append("paste:\(text)")
                return true
            },
            copyToClipboard: { _ in
                XCTFail("Copy fallback should not run when paste succeeds.")
            }
        )

        let result = await engine.insert("dictated text", preferredTarget: capturedTarget)

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(events, ["accessibilityInsert", "focusedTarget", "paste:dictated text"])
    }

    func testRecordingStartCopiesWhenCapturedTargetFailsAndSameTargetPasteFails() async {
        let capturedTarget = TextInsertionTarget(element: AXUIElementCreateSystemWide())
        var events: [String] = []
        var copiedText: String?

        let engine = TextInsertionEngine(
            focusedTargetProvider: {
                events.append("focusedTarget")
                return capturedTarget
            },
            accessibilityInserter: { _, _ in
                events.append("accessibilityInsert")
                return false
            },
            pasteFallback: { text in
                events.append("paste:\(text)")
                return false
            },
            copyToClipboard: { text in
                events.append("copy")
                copiedText = text
            }
        )

        let result = await engine.insert("dictated text", preferredTarget: capturedTarget)

        XCTAssertEqual(result, .copiedToClipboard)
        XCTAssertEqual(copiedText, "dictated text")
        XCTAssertEqual(events, ["accessibilityInsert", "focusedTarget", "accessibilityInsert", "paste:dictated text", "copy"])
    }

    func testRecordingStartCopiesWhenCapturedTargetIsMissingWithoutCurrentFocusOrPasteFallback() async {
        var events: [String] = []
        var copiedText: String?

        let engine = TextInsertionEngine(
            focusedTargetProvider: {
                events.append("focusedTarget")
                return nil
            },
            accessibilityInserter: { _, _ in
                XCTFail("Accessibility insertion should not run when captured target is missing in recording-start mode.")
                return false
            },
            pasteFallback: { _ in
                events.append("paste")
                return false
            },
            copyToClipboard: { text in
                events.append("copy")
                copiedText = text
            }
        )

        let result = await engine.insert("dictated text")

        XCTAssertEqual(result, .copiedToClipboard)
        XCTAssertEqual(copiedText, "dictated text")
        XCTAssertEqual(events, ["focusedTarget", "paste", "copy"])
    }

    func testTranscriptionFinishIgnoresCapturedTargetAndUsesFocusedTarget() async {
        let capturedTarget = TextInsertionTarget(element: AXUIElementCreateSystemWide())
        let focusedTarget = TextInsertionTarget(element: AXUIElementCreateApplication(getpid()))
        var events: [String] = []

        let engine = TextInsertionEngine(
            focusedTargetProvider: {
                events.append("focusedTarget")
                return focusedTarget
            },
            accessibilityInserter: { _, _ in
                events.append("accessibilityInsert")
                return true
            },
            pasteFallback: { _ in
                XCTFail("Paste fallback should not run when focused insertion succeeds.")
                return false
            },
            copyToClipboard: { _ in
                XCTFail("Copy fallback should not run when focused insertion succeeds.")
            }
        )

        let result = await engine.insert(
            "dictated text",
            preferredTarget: capturedTarget,
            targetBehavior: .transcriptionFinish
        )

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(events, ["focusedTarget", "accessibilityInsert"])
    }

    func testTranscriptionFinishFallsBackToPasteWhenCurrentAccessibilityInsertionFails() async {
        let capturedTarget = TextInsertionTarget(element: AXUIElementCreateSystemWide())
        var events: [String] = []

        let engine = TextInsertionEngine(
            focusedTargetProvider: {
                events.append("focusedTarget")
                return nil
            },
            accessibilityInserter: { _, _ in
                events.append("accessibilityInsert")
                return false
            },
            pasteFallback: { text in
                events.append("paste:\(text)")
                return true
            },
            copyToClipboard: { _ in
                XCTFail("Copy fallback should not run when paste succeeds.")
            }
        )

        let result = await engine.insert(
            "dictated text",
            preferredTarget: capturedTarget,
            targetBehavior: .transcriptionFinish
        )

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(events, ["focusedTarget", "paste:dictated text"])
    }

    func testTranscriptionFinishCopiesToClipboardWhenInsertionAndPasteFail() async {
        let capturedTarget = TextInsertionTarget(element: AXUIElementCreateSystemWide())
        var copiedText: String?

        let engine = TextInsertionEngine(
            focusedTargetProvider: { nil },
            accessibilityInserter: { _, _ in false },
            pasteFallback: { _ in false },
            copyToClipboard: { text in
                copiedText = text
            }
        )

        let result = await engine.insert(
            "dictated text",
            preferredTarget: capturedTarget,
            targetBehavior: .transcriptionFinish
        )

        XCTAssertEqual(result, .copiedToClipboard)
        XCTAssertEqual(copiedText, "dictated text")
    }

    func testInsertionTargetBehaviorStoreDefaultsToRecordingStartForMissingOrUnknownValues() {
        let suiteName = "InsertionTargetBehaviorStoreTests.missing"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = InsertionTargetBehaviorStore(defaults: defaults, key: "behavior")

        XCTAssertEqual(store.load(), .recordingStart)

        defaults.set("unknown", forKey: "behavior")
        XCTAssertEqual(store.load(), .recordingStart)
    }

    func testInsertionTargetBehaviorStorePersistsSelectedBehavior() {
        let suiteName = "InsertionTargetBehaviorStoreTests.persisted"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = InsertionTargetBehaviorStore(defaults: defaults, key: "behavior")

        store.save(.transcriptionFinish)

        XCTAssertEqual(store.load(), .transcriptionFinish)
    }
}
