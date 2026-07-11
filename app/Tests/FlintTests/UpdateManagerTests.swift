import XCTest
@testable import Flint

final class UpdateManagerTests: XCTestCase {
    func testValidConfigurationIsReady() throws {
        let manager = UpdateManager(
            metadata: validMetadata(),
            bundleURL: URL(fileURLWithPath: "/Applications/Flint.app")
        )

        let readiness = manager.readiness()

        XCTAssertEqual(
            readiness,
            .ready(UpdateConfiguration(
                bundleIdentifier: "com.example.Flint",
                bundleVersion: "42",
                shortVersion: "1.2.3",
                feedURL: try XCTUnwrap(URL(string: "https://updates.example.com/flint/appcast.xml"))
            ))
        )
    }

    func testInvalidAndNonHTTPSFeedURLsAreNotConfigured() {
        let invalidManager = UpdateManager(
            metadata: validMetadata(overrides: ["SUFeedURL": "not a url"]),
            bundleURL: URL(fileURLWithPath: "/Applications/Flint.app")
        )
        XCTAssertEqual(invalidManager.readiness(), .notConfigured(prerequisites: ["HTTPS SUFeedURL"]))

        let httpManager = UpdateManager(
            metadata: validMetadata(overrides: ["SUFeedURL": "http://updates.example.com/flint/appcast.xml"]),
            bundleURL: URL(fileURLWithPath: "/Applications/Flint.app")
        )
        XCTAssertEqual(httpManager.readiness(), .notConfigured(prerequisites: ["HTTPS SUFeedURL"]))
    }

    func testMalformedAndWrongLengthPublicKeysAreNotConfigured() {
        let malformedManager = UpdateManager(
            metadata: validMetadata(overrides: ["SUPublicEDKey": "not base64"]),
            bundleURL: URL(fileURLWithPath: "/Applications/Flint.app")
        )
        XCTAssertEqual(malformedManager.readiness(), .notConfigured(prerequisites: ["SUPublicEDKey"]))

        let wrongLengthManager = UpdateManager(
            metadata: validMetadata(overrides: ["SUPublicEDKey": Data(repeating: 0, count: 31).base64EncodedString()]),
            bundleURL: URL(fileURLWithPath: "/Applications/Flint.app")
        )
        XCTAssertEqual(wrongLengthManager.readiness(), .notConfigured(prerequisites: ["SUPublicEDKey"]))
    }

    func testMissingMetadataIsNotConfigured() {
        let manager = UpdateManager(
            metadata: [
                "CFBundleIdentifier": "",
                "CFBundleVersion": "  ",
                "SUFeedURL": "https://updates.example.com/flint/appcast.xml"
            ],
            bundleURL: URL(fileURLWithPath: "/Applications/Flint.app")
        )

        XCTAssertEqual(
            manager.readiness(),
            .notConfigured(prerequisites: [
                "CFBundleIdentifier",
                "CFBundleVersion",
                "CFBundleShortVersionString",
                "SUPublicEDKey"
            ])
        )
    }

    func testNonAppBundleIsNotConfigured() {
        let manager = UpdateManager(
            metadata: validMetadata(),
            bundleURL: URL(fileURLWithPath: "/usr/local/bin/flint")
        )

        XCTAssertEqual(
            manager.readiness(),
            .notConfigured(prerequisites: ["Application bundle packaging (.app)"])
        )
    }
}

private func validMetadata(overrides: [String: String] = [:]) -> [String: Any] {
    var metadata: [String: String] = [
        "CFBundleIdentifier": "com.example.Flint",
        "CFBundleVersion": "42",
        "CFBundleShortVersionString": "1.2.3",
        "SUFeedURL": "https://updates.example.com/flint/appcast.xml",
        "SUPublicEDKey": Data(repeating: 0, count: 32).base64EncodedString()
    ]
    metadata.merge(overrides) { _, new in new }
    return metadata
}
