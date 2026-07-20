import XCTest
@testable import Flint

final class FlintMenuBarIconTests: XCTestCase {
    func testMenuBarIconUsesCompactTemplateRendering() {
        let icon = FlintMenuBarIcon.make()

        XCTAssertEqual(icon.size, NSSize(width: 18, height: 18))
        XCTAssertTrue(icon.isTemplate)
        XCTAssertEqual(icon.accessibilityDescription, "Flint")
    }

    func testUpdateIconAddsABadgeAndAccessibleDescription() {
        let normal = FlintMenuBarIcon.make()
        let update = FlintMenuBarIcon.make(hasUpdate: true)

        XCTAssertNotEqual(normal.tiffRepresentation, update.tiffRepresentation)
        XCTAssertEqual(update.accessibilityDescription, "Flint, update available")
    }
}
