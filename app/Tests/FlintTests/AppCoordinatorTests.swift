import XCTest
@testable import Flint

final class AppCoordinatorTests: XCTestCase {
    func testCoordinatorExposesQuitActionToTheStatusMenu() {
        XCTAssertTrue(
            AppCoordinator.instancesRespond(to: #selector(AppCoordinator.quitApplication(_:)))
        )
    }
}
