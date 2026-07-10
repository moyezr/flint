import AppKit
import XCTest
@testable import Flint

final class ClipboardManagerTests: XCTestCase {
    private var pasteboard: NSPasteboard!
    private let manager = ClipboardManager()

    override func setUp() {
        super.setUp()
        pasteboard = NSPasteboard(name: NSPasteboard.Name("FlintTests-\(UUID().uuidString)"))
        pasteboard.clearContents()
    }

    override func tearDown() {
        pasteboard.clearContents()
        pasteboard = nil
        super.tearDown()
    }

    func testRestoresStringClipboardContents() {
        pasteboard.clearContents()
        pasteboard.setString("original clipboard", forType: .string)

        let savedItems = manager.snapshotItems(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("dictated text", forType: .string)

        manager.restore(savedItems, to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "original clipboard")
    }

    func testRestoresMultipleClipboardItemsAndTypes() {
        let first = NSPasteboardItem()
        first.setString("plain text", forType: .string)
        first.setString("<b>plain text</b>", forType: .html)

        let second = NSPasteboardItem()
        second.setString("https://example.com", forType: .URL)

        pasteboard.clearContents()
        XCTAssertTrue(pasteboard.writeObjects([first, second]))

        let savedItems = manager.snapshotItems(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString("replacement", forType: .string)

        manager.restore(savedItems, to: pasteboard)

        let restoredItems = pasteboard.pasteboardItems ?? []
        XCTAssertEqual(restoredItems.count, 2)
        XCTAssertEqual(restoredItems[0].string(forType: .string), "plain text")
        XCTAssertEqual(restoredItems[0].string(forType: .html), "<b>plain text</b>")
        XCTAssertEqual(restoredItems[1].string(forType: .URL), "https://example.com")
    }

    func testRestoresEmptyClipboardByClearingTemporaryText() {
        let savedItems = manager.snapshotItems(from: pasteboard)
        pasteboard.setString("temporary dictated text", forType: .string)

        manager.restore(savedItems, to: pasteboard)

        XCTAssertNil(pasteboard.string(forType: .string))
        XCTAssertEqual(pasteboard.pasteboardItems?.count ?? 0, 0)
    }

    func testDoesNotRestoreOverClipboardChangedAfterPasteSubmission() {
        pasteboard.setString("original clipboard", forType: .string)
        let savedItems = manager.snapshotItems(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("dictated text", forType: .string)
        let temporaryChangeCount = pasteboard.changeCount

        pasteboard.clearContents()
        pasteboard.setString("new clipboard content", forType: .string)

        XCTAssertFalse(
            manager.restoreIfUnchanged(
                savedItems,
                to: pasteboard,
                expectedChangeCount: temporaryChangeCount
            )
        )
        XCTAssertEqual(pasteboard.string(forType: .string), "new clipboard content")
    }

    func testRestoresClipboardWhenItHasNotChangedAfterPasteSubmission() {
        pasteboard.setString("original clipboard", forType: .string)
        let savedItems = manager.snapshotItems(from: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString("dictated text", forType: .string)

        XCTAssertTrue(
            manager.restoreIfUnchanged(
                savedItems,
                to: pasteboard,
                expectedChangeCount: pasteboard.changeCount
            )
        )
        XCTAssertEqual(pasteboard.string(forType: .string), "original clipboard")
    }
}
