import Foundation
import XCTest
@testable import Flint

final class AppUninstallerTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-uninstaller-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testValidatedApplicationURLAcceptsPackagedFlintBundle() throws {
        let applicationURL = try makeApplicationBundle()
        let uninstaller = makeUninstaller(applicationURL: applicationURL)

        XCTAssertEqual(try uninstaller.validatedApplicationURL(), applicationURL.standardizedFileURL)
    }

    func testValidatedApplicationURLRejectsDevelopmentExecutable() throws {
        let executableURL = tempRoot.appendingPathComponent("Flint")
        FileManager.default.createFile(atPath: executableURL.path, contents: Data())
        let uninstaller = makeUninstaller(applicationURL: executableURL)

        XCTAssertThrowsError(try uninstaller.validatedApplicationURL()) { error in
            XCTAssertEqual(error as? AppUninstaller.AppUninstallerError, .installedAppRequired)
        }
    }

    func testValidatedApplicationURLRejectsAnotherApplicationsBundle() throws {
        let applicationURL = try makeApplicationBundle()
        let uninstaller = makeUninstaller(
            applicationURL: applicationURL,
            bundleIdentifier: "com.example.NotFlint"
        )

        XCTAssertThrowsError(try uninstaller.validatedApplicationURL()) { error in
            XCTAssertEqual(
                error as? AppUninstaller.AppUninstallerError,
                .unexpectedBundleIdentifier("com.example.NotFlint")
            )
        }
    }

    func testValidatedApplicationURLRejectsReadOnlyDiskImageCopy() throws {
        let applicationURL = try makeApplicationBundle()
        let uninstaller = makeUninstaller(applicationURL: applicationURL, isVolumeReadOnly: { _ in true })

        XCTAssertThrowsError(try uninstaller.validatedApplicationURL()) { error in
            XCTAssertEqual(
                error as? AppUninstaller.AppUninstallerError,
                .applicationIsOnReadOnlyVolume(applicationURL.standardizedFileURL)
            )
        }
    }

    func testMoveApplicationToTrashRecyclesOnlyValidatedBundle() async throws {
        let applicationURL = try makeApplicationBundle()
        var recycledURLs: [URL] = []
        let trashURL = tempRoot.appendingPathComponent("Trash/Flint.app", isDirectory: true)
        let uninstaller = makeUninstaller(applicationURL: applicationURL, recycler: { urls in
            recycledURLs = urls
            return [applicationURL.standardizedFileURL: trashURL]
        })

        try await uninstaller.moveApplicationToTrash(applicationURL)

        XCTAssertEqual(recycledURLs, [applicationURL.standardizedFileURL])
    }

    func testMoveApplicationToTrashRequiresRecyclerConfirmation() async throws {
        let applicationURL = try makeApplicationBundle()
        let uninstaller = makeUninstaller(applicationURL: applicationURL, recycler: { _ in [:] })

        do {
            try await uninstaller.moveApplicationToTrash(applicationURL)
            XCTFail("Expected missing recycle confirmation to fail.")
        } catch {
            XCTAssertEqual(
                error as? AppUninstaller.AppUninstallerError,
                .applicationWasNotMovedToTrash(applicationURL.standardizedFileURL)
            )
        }
    }

    private func makeApplicationBundle() throws -> URL {
        let url = tempRoot.appendingPathComponent("Flint.app", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeUninstaller(
        applicationURL: URL,
        bundleIdentifier: String? = AppUninstaller.expectedBundleIdentifier,
        isVolumeReadOnly: @escaping (URL) throws -> Bool = { _ in false },
        recycler: @escaping AppUninstaller.Recycler = { urls in
            Dictionary(uniqueKeysWithValues: urls.map { ($0, $0) })
        }
    ) -> AppUninstaller {
        AppUninstaller(
            applicationURLProvider: { applicationURL },
            bundleIdentifierProvider: { bundleIdentifier },
            isVolumeReadOnly: isVolumeReadOnly,
            recycler: recycler
        )
    }
}
