import Foundation
import XCTest
@testable import Flint

final class UpdateManagerTests: XCTestCase {
    func testValidConfigurationIsReady() throws {
        let manager = UpdateManager(
            metadata: validMetadata(),
            bundleURL: URL(fileURLWithPath: "/Applications/Flint.app")
        )

        XCTAssertEqual(
            manager.readiness(),
            .ready(UpdateConfiguration(
                bundleIdentifier: "com.example.Flint",
                currentVersion: "1.2.3",
                currentBuild: "42",
                manifestURL: try XCTUnwrap(URL(string: "https://updates.example.com/api/releases/latest"))
            ))
        )
    }

    func testInvalidAndNonHTTPSManifestURLsAreNotConfigured() {
        let invalidManager = UpdateManager(
            metadata: validMetadata(overrides: ["FlintUpdateManifestURL": "not a url"]),
            bundleURL: URL(fileURLWithPath: "/Applications/Flint.app")
        )
        XCTAssertEqual(
            invalidManager.readiness(),
            .notConfigured(prerequisites: ["HTTPS FlintUpdateManifestURL"])
        )

        let httpManager = UpdateManager(
            metadata: validMetadata(overrides: ["FlintUpdateManifestURL": "http://updates.example.com/latest"]),
            bundleURL: URL(fileURLWithPath: "/Applications/Flint.app")
        )
        XCTAssertEqual(
            httpManager.readiness(),
            .notConfigured(prerequisites: ["HTTPS FlintUpdateManifestURL"])
        )
    }

    func testMissingMetadataIsNotConfigured() {
        let manager = UpdateManager(
            metadata: [
                "CFBundleIdentifier": "",
                "CFBundleVersion": "  ",
                "FlintUpdateManifestURL": "https://updates.example.com/latest"
            ],
            bundleURL: URL(fileURLWithPath: "/Applications/Flint.app")
        )

        XCTAssertEqual(
            manager.readiness(),
            .notConfigured(prerequisites: [
                "CFBundleIdentifier",
                "CFBundleVersion",
                "CFBundleShortVersionString"
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

    func testCheckDetectsNewerBetaVersion() async throws {
        let releaseURL = try XCTUnwrap(URL(string: "https://example.com/download"))
        let manager = managerReturningManifest(
            currentVersion: "0.1.0-beta.3",
            currentBuild: "3",
            manifest: """
            {
              "version": "0.1.0-beta.10",
              "build": "10",
              "downloadURL": "\(releaseURL.absoluteString)",
              "notes": ["Smoother updates"]
            }
            """
        )

        let result = try await manager.checkForUpdates()
        XCTAssertEqual(
            result,
            .updateAvailable(UpdateRelease(
                version: "0.1.0-beta.10",
                build: "10",
                downloadURL: releaseURL,
                notes: ["Smoother updates"]
            ))
        )
    }

    func testStableReleaseIsNewerThanPrerelease() async throws {
        let manager = managerReturningManifest(
            currentVersion: "1.0.0-beta.9",
            currentBuild: "9",
            manifest: validManifest(version: "1.0.0", build: "1")
        )

        guard case .updateAvailable = try await manager.checkForUpdates() else {
            return XCTFail("Expected a stable release to supersede its prerelease.")
        }
    }

    func testSameVersionWithNewerBuildIsAnUpdate() async throws {
        let manager = managerReturningManifest(
            currentVersion: "1.2.3",
            currentBuild: "42",
            manifest: validManifest(version: "1.2.3", build: "43")
        )

        guard case .updateAvailable = try await manager.checkForUpdates() else {
            return XCTFail("Expected a newer build to be available.")
        }
    }

    func testOlderOrSameReleaseIsUpToDate() async throws {
        let manager = managerReturningManifest(
            currentVersion: "1.2.3",
            currentBuild: "42",
            manifest: validManifest(version: "1.2.3", build: "42")
        )

        let result = try await manager.checkForUpdates()
        XCTAssertEqual(result, .upToDate)
    }

    func testRejectsInsecureDownloadURL() async {
        let manager = managerReturningManifest(
            currentVersion: "1.0.0",
            currentBuild: "1",
            manifest: validManifest(version: "1.1.0", build: "2", downloadURL: "http://example.com")
        )

        do {
            _ = try await manager.checkForUpdates()
            XCTFail("Expected an invalid manifest error.")
        } catch {
            XCTAssertEqual(error as? UpdateCheckError, .invalidManifest)
        }
    }

    func testCheckPolicyRunsAtMostDaily() {
        let policy = UpdateCheckPolicy(interval: 60)
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertTrue(policy.shouldCheck(lastSuccessfulCheck: nil, now: now))
        XCTAssertFalse(policy.shouldCheck(lastSuccessfulCheck: now.addingTimeInterval(-59), now: now))
        XCTAssertTrue(policy.shouldCheck(lastSuccessfulCheck: now.addingTimeInterval(-60), now: now))
    }

    func testCheckStorePersistsSuccessfulCheckAndNotification() throws {
        let suiteName = "UpdateManagerTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UpdateCheckStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 1_234)

        store.markSuccessfulCheck(at: date)
        store.markNotified(version: "2.0.0")

        XCTAssertEqual(store.lastSuccessfulCheck, date)
        XCTAssertEqual(store.lastNotifiedVersion, "2.0.0")
    }
}

private func validMetadata(overrides: [String: String] = [:]) -> [String: Any] {
    var metadata: [String: String] = [
        "CFBundleIdentifier": "com.example.Flint",
        "CFBundleVersion": "42",
        "CFBundleShortVersionString": "1.2.3",
        "FlintUpdateManifestURL": "https://updates.example.com/api/releases/latest"
    ]
    metadata.merge(overrides) { _, new in new }
    return metadata
}

private func managerReturningManifest(
    currentVersion: String,
    currentBuild: String,
    manifest: String
) -> UpdateManager {
    UpdateManager(
        metadata: validMetadata(overrides: [
            "CFBundleShortVersionString": currentVersion,
            "CFBundleVersion": currentBuild
        ]),
        bundleURL: URL(fileURLWithPath: "/Applications/Flint.app"),
        dataLoader: { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Data(manifest.utf8), response)
        }
    )
}

private func validManifest(
    version: String,
    build: String,
    downloadURL: String = "https://example.com/download"
) -> String {
    """
    {
      "version": "\(version)",
      "build": "\(build)",
      "downloadURL": "\(downloadURL)"
    }
    """
}
