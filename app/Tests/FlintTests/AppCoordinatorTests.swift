import XCTest
@testable import Flint

final class AppCoordinatorTests: XCTestCase {
    func testCoordinatorExposesQuitActionToTheStatusMenu() {
        XCTAssertTrue(
            AppCoordinator.instancesRespond(to: #selector(AppCoordinator.quitApplication(_:)))
        )
    }

    @MainActor
    func testStatusMenuUsesExplicitEnablementSoQuitIsNotDisabledByValidation() {
        let menu = AppCoordinator.makeStatusMenu()
        let quitItem = AppCoordinator.makeQuitMenuItem()

        XCTAssertFalse(menu.autoenablesItems)
        XCTAssertTrue(quitItem.isEnabled)
        XCTAssertEqual(quitItem.title, "Quit Flint")
        XCTAssertEqual(quitItem.action, #selector(AppCoordinator.quitApplication(_:)))
    }
}
