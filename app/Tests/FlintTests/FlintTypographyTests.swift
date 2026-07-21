import AppKit
import XCTest
@testable import Flint

@MainActor
final class FlintTypographyTests: XCTestCase {
    func testLandingTypefaceFamiliesAreTheNativeOnboardingFamilies() {
        XCTAssertEqual(FlintTypography.headingFamily, "Space Grotesk")
        XCTAssertEqual(FlintTypography.bodyFamily, "Inter")
        XCTAssertEqual(FlintTypography.monoFamily, "IBM Plex Mono")
    }

    func testBundledTypefaceFilesAndLicensesArePresent() {
        let fontURLs = FlintTypography.bundledFontURLs()
        let licenseURLs = FlintTypography.bundledFontLicenseURLs()

        XCTAssertEqual(fontURLs.count, FlintTypography.bundledFontNames.count)
        XCTAssertEqual(licenseURLs.count, FlintTypography.bundledFontLicenseNames.count)
        XCTAssertTrue(fontURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertTrue(licenseURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
    }

    func testBundledTypefacesRegisterForTheProcess() {
        FlintTypography.registerBundledFonts()

        let families = Set(NSFontManager.shared.availableFontFamilies)
        XCTAssertTrue(families.contains(FlintTypography.headingFamily))
        XCTAssertTrue(families.contains(FlintTypography.bodyFamily))
        XCTAssertTrue(families.contains(FlintTypography.monoFamily))
        XCTAssertNotNil(NSFont(name: "SpaceGrotesk-Medium", size: 16))
        XCTAssertNotNil(NSFont(name: "SpaceGrotesk-Bold", size: 16))
        XCTAssertNotNil(NSFont(name: "Inter-Regular", size: 16))
        XCTAssertNotNil(NSFont(name: "Inter-Medium", size: 16))
        XCTAssertNotNil(NSFont(name: "Inter-SemiBold", size: 16))
        XCTAssertNotNil(NSFont(name: "IBMPlexMono-SemiBold", size: 16))
    }
}
