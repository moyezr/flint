import AppKit
import ApplicationServices
import XCTest
@testable import Flint

@MainActor
final class TextInsertionIntegrationTests: XCTestCase {
    func testTextEditInsertionAndClipboardPreservation() async throws {
        try requireDesktopAccessibility()

        _ = try runAppleScript(
            """
            tell application "TextEdit"
                activate
                make new document
                set text of front document to "Flint compatibility baseline"
            end tell
            """
        )
        defer {
            _ = try? runAppleScript(
                """
                tell application "TextEdit"
                    close front document saving no
                end tell
                """
            )
        }

        try await Task.sleep(for: .milliseconds(500))
        let originalClipboard = "Flint clipboard sentinel \(UUID().uuidString)"
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.setString(originalClipboard, forType: .string))

        let result = await TextInsertionEngine().insert(
            " Flint compatibility insertion",
            targetBehavior: .transcriptionFinish
        )
        XCTAssertEqual(result, .inserted)

        try await Task.sleep(for: .seconds(1))
        let documentText = try runAppleScript(
            """
            tell application "TextEdit"
                get text of front document
            end tell
            """
        )
        XCTAssertEqual(documentText.components(separatedBy: "Flint compatibility insertion").count - 1, 1)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), originalClipboard)
    }

    func testSafariInputInsertionAndClipboardPreservation() async throws {
        try await assertBrowserInputInsertion(
            applicationName: "Safari",
            bundleIdentifier: "com.apple.Safari",
            createDocument: "make new document",
            setDocumentURL: "set URL of front document to",
            closeDocument: "close front document"
        )
    }

    private func requireDesktopAccessibility() throws {
        guard ProcessInfo.processInfo.environment["FLINT_RUN_ACCESSIBILITY_INTEGRATION"] == "1" else {
            throw XCTSkip("Set FLINT_RUN_ACCESSIBILITY_INTEGRATION=1 to run desktop accessibility probes.")
        }
        guard AXIsProcessTrusted() else {
            throw XCTSkip("Grant Accessibility permission to the test runner before running desktop probes.")
        }
    }

    private func assertBrowserInputInsertion(
        applicationName: String,
        bundleIdentifier: String,
        createDocument: String,
        setDocumentURL: String,
        closeDocument: String
    ) async throws {
        try requireDesktopAccessibility()
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil else {
            throw XCTSkip("\(applicationName) is not installed on this QA Mac.")
        }

        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/compatibility-input.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL.path))

        _ = try runAppleScript(
            """
            tell application "\(applicationName)"
                \(createDocument)
                \(setDocumentURL) "\(fixtureURL.absoluteString)"
                activate
            end tell
            """
        )
        defer {
            _ = try? runAppleScript(
                """
                tell application "\(applicationName)"
                    \(closeDocument)
                end tell
                """
            )
        }

        try await Task.sleep(for: .seconds(2))
        let expectedText = "Flint \(applicationName) insertion"
        let originalClipboard = "Flint \(applicationName) clipboard sentinel \(UUID().uuidString)"
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.setString(originalClipboard, forType: .string))

        let browser = try XCTUnwrap(
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first
        )
        let browserApplicationElement = AXUIElementCreateApplication(browser.processIdentifier)
        let browserInput = try XCTUnwrap(firstEditableTextElement(in: browserApplicationElement))
        XCTAssertTrue(focus(browserInput))
        try await Task.sleep(for: .milliseconds(200))

        let result = await TextInsertionEngine().insert(
            expectedText,
            targetBehavior: .transcriptionFinish
        )
        XCTAssertEqual(result, .inserted)

        try await Task.sleep(for: .seconds(1))
        let insertedValue = try XCTUnwrap(accessibilityValue(of: browserInput))
        XCTAssertEqual(insertedValue.components(separatedBy: expectedText).count - 1, 1)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), originalClipboard)
    }

    private func accessibilityValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private func focus(_ element: AXUIElement) -> Bool {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue,
              let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID() else {
            return false
        }

        var position = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              let source = CGEventSource(stateID: .combinedSessionState),
              let mouseDown = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseDown,
                mouseCursorPosition: CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2),
                mouseButton: .left
              ),
              let mouseUp = CGEvent(
                mouseEventSource: source,
                mouseType: .leftMouseUp,
                mouseCursorPosition: CGPoint(x: position.x + size.width / 2, y: position.y + size.height / 2),
                mouseButton: .left
              ) else {
            return false
        }

        mouseDown.post(tap: .cghidEventTap)
        mouseUp.post(tap: .cghidEventTap)
        return true
    }

    private func firstEditableTextElement(in root: AXUIElement) -> AXUIElement? {
        var pending = [(element: root, isInsideWebArea: false)]
        var visitedElementCount = 0

        while let item = pending.popLast(), visitedElementCount < 1_000 {
            visitedElementCount += 1
            let element = item.element
            var roleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleValue) == .success,
                  let role = roleValue as? String else {
                continue
            }
            let isInsideWebArea = item.isInsideWebArea || role == "AXWebArea"
            if isInsideWebArea && (role == kAXTextFieldRole || role == kAXTextAreaRole) {
                return element
            }

            var childrenValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenValue) == .success,
                  let children = childrenValue as? [AXUIElement] else {
                continue
            }
            pending.append(contentsOf: children.map { (element: $0, isInsideWebArea: isInsideWebArea) })
        }
        return nil
    }

    private func runAppleScript(_ source: String) throws -> String {
        guard let script = NSAppleScript(source: source) else {
            throw NSError(domain: "TextInsertionIntegrationTests", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unable to compile AppleScript."
            ])
        }

        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            throw NSError(domain: "TextInsertionIntegrationTests", code: 2, userInfo: [
                NSLocalizedDescriptionKey: error.description
            ])
        }
        return result.stringValue ?? ""
    }
}
