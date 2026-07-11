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
        try requireDesktopAccessibility()
        guard FileManager.default.fileExists(atPath: "/Applications/Safari.app") else {
            throw XCTSkip("Safari is not installed on this QA Mac.")
        }

        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/compatibility-input.html")
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixtureURL.path))

        _ = try runAppleScript(
            """
            tell application "Safari"
                make new document
                set URL of front document to "\(fixtureURL.absoluteString)"
                activate
            end tell
            """
        )
        defer {
            _ = try? runAppleScript(
                """
                tell application "Safari"
                    close front document
                end tell
                """
            )
        }

        try await Task.sleep(for: .seconds(2))
        let originalClipboard = "Flint Safari clipboard sentinel \(UUID().uuidString)"
        NSPasteboard.general.clearContents()
        XCTAssertTrue(NSPasteboard.general.setString(originalClipboard, forType: .string))

        let safari = try XCTUnwrap(
            NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first
        )
        let safariApplicationElement = AXUIElementCreateApplication(safari.processIdentifier)
        let safariInput = try XCTUnwrap(firstEditableTextElement(in: safariApplicationElement))
        XCTAssertEqual(
            AXUIElementSetAttributeValue(
                safariInput,
                kAXFocusedAttribute as CFString,
                true as CFTypeRef
            ),
            .success
        )
        try await Task.sleep(for: .milliseconds(200))

        let engine = TextInsertionEngine()
        let result = await engine.insert(
            "Flint Safari insertion",
            targetBehavior: .transcriptionFinish
        )
        XCTAssertEqual(result, .inserted)

        try await Task.sleep(for: .seconds(1))
        let insertedValue = try XCTUnwrap(accessibilityValue(of: safariInput))
        XCTAssertEqual(insertedValue.components(separatedBy: "Flint Safari insertion").count - 1, 1)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), originalClipboard)
    }

    private func requireDesktopAccessibility() throws {
        guard ProcessInfo.processInfo.environment["FLINT_RUN_ACCESSIBILITY_INTEGRATION"] == "1" else {
            throw XCTSkip("Set FLINT_RUN_ACCESSIBILITY_INTEGRATION=1 to run desktop accessibility probes.")
        }
        guard AXIsProcessTrusted() else {
            throw XCTSkip("Grant Accessibility permission to the test runner before running desktop probes.")
        }
    }

    private func accessibilityValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success else {
            return nil
        }
        return value as? String
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
