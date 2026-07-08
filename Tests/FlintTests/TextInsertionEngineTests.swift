import ApplicationServices
import XCTest
@testable import Flint

@MainActor
final class TextInsertionEngineTests: XCTestCase {
    func testInsertPrefersCapturedTargetBeforeFocusedTarget() async {
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

    func testInsertFallsBackToFocusedTargetWhenCapturedTargetFails() async {
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
                return events.filter { $0 == "accessibilityInsert" }.count == 2
            },
            pasteFallback: { _ in
                XCTFail("Paste fallback should not run when focused insertion succeeds.")
                return false
            },
            copyToClipboard: { _ in
                XCTFail("Copy fallback should not run when focused insertion succeeds.")
            }
        )

        let result = await engine.insert("dictated text", preferredTarget: capturedTarget)

        XCTAssertEqual(result, .inserted)
        XCTAssertEqual(events, ["accessibilityInsert", "focusedTarget", "accessibilityInsert"])
    }

    func testInsertFallsBackToPasteWhenAccessibilityInsertionFails() async {
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

    func testInsertCopiesToClipboardWhenInsertionAndPasteFail() async {
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

        let result = await engine.insert("dictated text", preferredTarget: capturedTarget)

        XCTAssertEqual(result, .copiedToClipboard)
        XCTAssertEqual(copiedText, "dictated text")
    }
}
