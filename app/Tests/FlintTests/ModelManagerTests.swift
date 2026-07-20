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

    func testHardwareRecommendationUsesAccurateOnAppleSiliconAndBalancedOnIntel() {
        XCTAssertEqual(ModelRecommendation(isAppleSilicon: true).tier, .accurate)
        XCTAssertFalse(ModelRecommendation(isAppleSilicon: true).allowsOnboardingChoice)
        XCTAssertEqual(ModelRecommendation(isAppleSilicon: false).tier, .balanced)
        XCTAssertTrue(ModelRecommendation(isAppleSilicon: false).allowsOnboardingChoice)
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
            try self.createModelFolder(named: "base", in: downloadBase!)
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
            return try self.createModelFolder(named: "downloaded-\(variant)", in: downloadBase!)
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
            return try self.createModelFolder(named: "downloaded-\(variant)", in: downloadBase!)
        }

        let firstMetadata = try await manager.downloadModel(for: .balanced)
        let secondMetadata = try await manager.downloadModel(for: .balanced)

        XCTAssertEqual(requestedVariants, ["base"])
        XCTAssertEqual(secondMetadata, firstMetadata)
        XCTAssertTrue(secondMetadata.isInstalled)
    }

    func testDownloadRejectsPathOutsideCacheRoot() async throws {
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-outside-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideRoot) }

        let manager = makeManager { _, _, _ in outsideRoot }
        do {
            _ = try await manager.downloadModel(for: .accurate)
            XCTFail("A downloader result outside the model cache must be rejected.")
        } catch {
            XCTAssertEqual(
                error as? ModelManager.ModelManagerError,
                .downloadedPathOutsideCacheRoot(outsideRoot)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideRoot.path))
        XCTAssertFalse(manager.metadata(for: .accurate).isInstalled)
    }

    func testDeleteRemovesAndClearsSavedPathInsideCacheRoot() async throws {
        let manager = makeManager { _, downloadBase, _ in
            try self.createModelFolder(named: "base", in: downloadBase!)
        }
        let metadata = try await manager.downloadModel(for: .balanced)
        let folder = try XCTUnwrap(metadata.installedFolder)

        try manager.deleteModel(for: .balanced)

        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        XCTAssertFalse(manager.metadata(for: .balanced).isInstalled)
    }

    func testDeleteAllCachedModelsRemovesCacheContentsAndClearsReferences() async throws {
        let manager = makeManager { variant, downloadBase, _ in
            try self.createModelFolder(named: "downloaded-\(variant)", in: downloadBase!)
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
        defaults.set(outsideRoot.path, forKey: "installedModelFolder.accurate")
        let manager = makeManager()

        XCTAssertThrowsError(try manager.deleteAllCachedModelsAndReferences()) { error in
            XCTAssertEqual(
                error as? ModelManager.ModelManagerError,
                .savedPathOutsideCacheRoot(outsideRoot)
            )
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outsideRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanFile.path))
        XCTAssertFalse(manager.metadata(for: .accurate).isInstalled)
    }

    func testTranscriptionConfigDescriptorUsesInstalledFolderWhenPresent() async throws {
        let manager = makeManager { _, downloadBase, _ in
            try self.createModelFolder(named: "base", in: downloadBase!)
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

    func testEmptyDownloadedFolderIsRejectedAndNotMarkedInstalled() async throws {
        let manager = makeManager { _, downloadBase, _ in
            let folder = downloadBase!.appendingPathComponent("empty", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }

        do {
            _ = try await manager.downloadModel(for: .fast)
            XCTFail("An empty model directory must not be accepted as installed.")
        } catch {
            XCTAssertEqual(
                error as? ModelManager.ModelManagerError,
                .downloadedModelIsEmpty(tempRoot.appendingPathComponent("empty", isDirectory: true))
            )
        }
        XCTAssertFalse(manager.metadata(for: .fast).isInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempRoot.appendingPathComponent("empty").path))
    }

    func testChangedPayloadIsRemovedBeforeDownloadingReplacement() async throws {
        var downloadCount = 0
        let manager = makeManager { _, downloadBase, _ in
            downloadCount += 1
            return try self.createModelFolder(named: "base", in: downloadBase!, contents: Data([UInt8(downloadCount)]))
        }

        let initial = try await manager.downloadModel(for: .balanced)
        let folder = try XCTUnwrap(initial.installedFolder)
        _ = FileManager.default.createFile(
            atPath: folder.appendingPathComponent("unexpected.bin").path,
            contents: Data([9])
        )

        XCTAssertFalse(manager.metadata(for: .balanced).isInstalled)
        _ = try await manager.downloadModel(for: .balanced)

        XCTAssertEqual(downloadCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("unexpected.bin").path))
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

    private func createModelFolder(named name: String, in downloadBase: URL, contents: Data = Data([1])) throws -> URL {
        let folder = downloadBase.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        _ = FileManager.default.createFile(
            atPath: folder.appendingPathComponent("model.bin").path,
            contents: contents
        )
        return folder
    }
}
