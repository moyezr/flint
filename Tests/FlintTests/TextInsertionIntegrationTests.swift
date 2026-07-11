import AppKit
import ApplicationServices
import XCTest
@testable import Flint

@MainActor
final class TextInsertionIntegrationTests: XCTestCase {
    func testTextEditInsertionAndClipboardPreservation() async throws {
        guard ProcessInfo.processInfo.environment["FLINT_RUN_ACCESSIBILITY_INTEGRATION"] == "1" else {
            throw XCTSkip("Set FLINT_RUN_ACCESSIBILITY_INTEGRATION=1 to run desktop accessibility probes.")
        }
        guard AXIsProcessTrusted() else {
            throw XCTSkip("Grant Accessibility permission to the test runner before running desktop probes.")
        }

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
