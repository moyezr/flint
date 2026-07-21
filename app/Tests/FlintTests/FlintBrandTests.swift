import XCTest
@testable import Flint

final class FlintBrandTests: XCTestCase {
    func testNativeBrandTokensMatchTheLandingWarmTheme() {
        XCTAssertEqual(FlintBrand.signalHex, 0xFF4F1F)
        XCTAssertEqual(FlintBrand.paperHex, 0xF8F7F3)
        XCTAssertEqual(FlintBrand.mistHex, 0xE9E8E1)
        XCTAssertEqual(FlintBrand.inkHex, 0x121412)
        XCTAssertEqual(FlintBrand.deepHex, 0x151914)
        XCTAssertEqual(FlintBrand.mutedHex, 0x62675E)
        XCTAssertEqual(FlintBrand.lineHex, 0xC9CDC2)
    }
}
