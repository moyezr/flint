import XCTest
@testable import Flint

final class ModelManagerTests: XCTestCase {
    private var defaults: UserDefaults!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        defaults = UserDefaults(suiteName: "FlintTests.ModelManager.\(UUID().uuidString)")!
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-model-manager-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        defaults = nil
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testDefaultSelectionFallsBackToBalanced() {
        let manager = makeManager()

        XCTAssertEqual(manager.selectedTier(), .balanced)
    }

    func testSelectionPersists() {
        let manager = makeManager()

        manager.saveSelectedTier(.accurate)

        XCTAssertEqual(manager.selectedTier(), .accurate)
    }

    func testUnknownSelectionFallsBackToBalanced() {
        defaults.set("unknown-tier", forKey: "selectedModelTier")
        let manager = makeManager()

        XCTAssertEqual(manager.selectedTier(), .balanced)
    }

    func testMetadataListsThreeTiers() {
        let manager = makeManager()

        let metadata = manager.metadata()

        XCTAssertEqual(metadata.map(\.tier), [.fast, .balanced, .accurate])
        XCTAssertEqual(metadata.map(\.displayName), ["Fast", "Balanced", "Accurate"])
        XCTAssertEqual(metadata.map(\.modelName), ["tiny", "base", "large-v3-v20240930_626MB"])
    }

    func testInstalledStateFollowsSavedPathExistence() async throws {
        let manager = makeManager { _, downloadBase, _ in
            let folder = downloadBase!.appendingPathComponent("base", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }

        XCTAssertFalse(manager.metadata(for: .balanced).isInstalled)
        let downloaded = try await manager.downloadModel(for: .balanced)
        XCTAssertTrue(downloaded.isInstalled)

        try FileManager.default.removeItem(at: downloaded.installedFolder!)

        XCTAssertFalse(manager.metadata(for: .balanced).isInstalled)
    }

    func testFakeDownloaderSavesReturnedPathWithoutNetwork() async throws {
        var requestedVariants: [String] = []
        let manager = makeManager { variant, downloadBase, _ in
            requestedVariants.append(variant)
            let folder = downloadBase!.appendingPathComponent("downloaded-\(variant)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }

        let metadata = try await manager.downloadModel(for: .fast)

        XCTAssertEqual(requestedVariants, ["tiny"])
        XCTAssertTrue(metadata.isInstalled)
        XCTAssertEqual(metadata.installedFolder?.lastPathComponent, "downloaded-tiny")
    }

    func testDownloadModelReturnsInstalledMetadataWithoutInvokingDownloaderAgain() async throws {
        var requestedVariants: [String] = []
        let manager = makeManager { variant, downloadBase, _ in
            requestedVariants.append(variant)
            let folder = downloadBase!.appendingPathComponent("downloaded-\(variant)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }

        let firstMetadata = try await manager.downloadModel(for: .balanced)
        let secondMetadata = try await manager.downloadModel(for: .balanced)

        XCTAssertEqual(requestedVariants, ["base"])
        XCTAssertEqual(secondMetadata, firstMetadata)
        XCTAssertTrue(secondMetadata.isInstalled)
    }

    func testDeleteRefusesSavedPathOutsideCacheRoot() async throws {
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-outside-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideRoot) }

        let manager = makeManager { _, _, _ in outsideRoot }
        try await manager.downloadModel(for: .accurate)

        XCTAssertThrowsError(try manager.deleteModel(for: .accurate)) { error in
            XCTAssertEqual(
                error as? ModelManager.ModelManagerError,
                .savedPathOutsideCacheRoot(outsideRoot)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideRoot.path))
    }

    func testDeleteRemovesAndClearsSavedPathInsideCacheRoot() async throws {
        let manager = makeManager { _, downloadBase, _ in
            let folder = downloadBase!.appendingPathComponent("base", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        let metadata = try await manager.downloadModel(for: .balanced)
        let folder = try XCTUnwrap(metadata.installedFolder)

        try manager.deleteModel(for: .balanced)

        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertFalse(manager.metadata(for: .balanced).isInstalled)
    }

    func testDeleteAllCachedModelsRemovesCacheContentsAndClearsReferences() async throws {
        let manager = makeManager { variant, downloadBase, _ in
            let folder = downloadBase!.appendingPathComponent("downloaded-\(variant)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        try await manager.downloadModel(for: .fast)
        try await manager.downloadModel(for: .balanced)
        let orphanFile = tempRoot.appendingPathComponent("orphan.bin")
        FileManager.default.createFile(atPath: orphanFile.path, contents: Data([1]))

        try manager.deleteAllCachedModelsAndReferences()

        XCTAssertFalse(manager.metadata(for: .fast).isInstalled)
        XCTAssertFalse(manager.metadata(for: .balanced).isInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanFile.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil),
            []
        )
    }

    func testDeleteAllCachedModelsRefusesSavedPathOutsideCacheRootBeforeDeletingAnything() async throws {
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-outside-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideRoot) }
        let orphanFile = tempRoot.appendingPathComponent("orphan.bin")
        FileManager.default.createFile(atPath: orphanFile.path, contents: Data([1]))
        let manager = makeManager { _, _, _ in outsideRoot }
        try await manager.downloadModel(for: .accurate)

        XCTAssertThrowsError(try manager.deleteAllCachedModelsAndReferences()) { error in
            XCTAssertEqual(
                error as? ModelManager.ModelManagerError,
                .savedPathOutsideCacheRoot(outsideRoot)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanFile.path))
        XCTAssertTrue(manager.metadata(for: .accurate).isInstalled)
    }

    func testTranscriptionConfigDescriptorUsesInstalledFolderWhenPresent() async throws {
        let manager = makeManager { _, downloadBase, _ in
            let folder = downloadBase!.appendingPathComponent("base", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        let metadata = try await manager.downloadModel(for: .balanced)
        let descriptor = manager.configurationDescriptor(for: .balanced)

        let config = TranscriptionEngine.whisperKitConfigDescriptor(for: descriptor)

        XCTAssertNil(config.model)
        XCTAssertEqual(config.downloadBase, tempRoot)
        XCTAssertEqual(config.modelFolder, metadata.installedFolder?.path)
    }

    func testTranscriptionConfigDescriptorUsesModelAndDownloadBaseWhenNotInstalled() {
        let manager = makeManager()
        let descriptor = manager.configurationDescriptor(for: .accurate)

        let config = TranscriptionEngine.whisperKitConfigDescriptor(for: descriptor)

        XCTAssertEqual(config.model, "large-v3-v20240930_626MB")
        XCTAssertEqual(config.downloadBase, tempRoot)
        XCTAssertNil(config.modelFolder)
    }

    private func makeManager(
        downloader: @escaping ModelManager.Downloader = { _, _, _ in
            XCTFail("Unexpected production-style download in unit test.")
            return URL(fileURLWithPath: "/unexpected", isDirectory: true)
        }
    ) -> ModelManager {
        ModelManager(
            defaults: defaults,
            modelCacheRoot: tempRoot,
            downloader: downloader
        )
    }
}
