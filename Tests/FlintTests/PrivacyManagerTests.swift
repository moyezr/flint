import XCTest
@testable import Flint

final class PrivacyManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "FlintTests.PrivacyManager.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-privacy-manager-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        tempRoot = nil
        try super.tearDownWithError()
    }

    func testSnapshotShowsPlainPrivacyRowsPathsAndHistoryStatus() {
        var settings = AppSettings.default
        settings.storeHistory = true
        AppSettingsStore(defaults: defaults).save(settings)
        DictionaryEngine(userDefaults: defaults).addReplacement(
            heardPhrase: "live kit",
            preferredReplacement: "LiveKit"
        )
        let manager = makePrivacyManager(permissionSnapshot: PermissionSnapshot(statuses: [
            PermissionStatus(kind: .microphone, readiness: .ready),
            PermissionStatus(kind: .accessibility, readiness: .denied),
            PermissionStatus(kind: .inputMonitoring, readiness: .ready)
        ]))

        let snapshot = manager.snapshot()

        XCTAssertEqual(snapshot.statusRows.first { $0.id == "transcription" }?.value, "Local")
        XCTAssertEqual(snapshot.statusRows.first { $0.id == "history" }?.value, "On")
        XCTAssertEqual(snapshot.statusRows.first { $0.id == "telemetry" }?.detail, "Telemetry is not implemented.")
        XCTAssertEqual(snapshot.permissionStatuses.map(\.kind), [.microphone, .accessibility, .inputMonitoring])
        XCTAssertEqual(snapshot.dataLocations.first { $0.id == "settings" }?.path, "Test UserDefaults \(suiteName!)")
        XCTAssertEqual(snapshot.dataLocations.first { $0.id == "vocabulary" }?.path, "Test UserDefaults \(suiteName!)")
        XCTAssertEqual(snapshot.dataLocations.first { $0.id == "model-cache" }?.path, tempRoot.path)
        XCTAssertEqual(
            snapshot.dataLocations.first { $0.id == "vocabulary" }?.detail,
            "1 custom entries stored under UserDefaults key dictionary.customReplacements."
        )
    }

    func testDeleteAllLocalDataResetsSettingsVocabularyAndModelCache() async throws {
        var settings = AppSettings.default
        settings.shortcutSettings = ShortcutSettings(option: .commandShiftSpace, behavior: .toggle)
        settings.cleanupMode = .email
        settings.selectedModelTier = .accurate
        settings.storeHistory = true
        settings.hasCompletedOnboarding = true
        AppSettingsStore(defaults: defaults).save(settings)
        DictionaryEngine(userDefaults: defaults).addReplacement(
            heardPhrase: "live kit",
            preferredReplacement: "LiveKit"
        )
        let orphanCacheFile = tempRoot.appendingPathComponent("orphan.bin")
        FileManager.default.createFile(atPath: orphanCacheFile.path, contents: Data([1, 2, 3]))
        let modelManager = makeModelManager { variant, downloadBase, _ in
            let folder = downloadBase!.appendingPathComponent("downloaded-\(variant)", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        }
        try await modelManager.downloadModel(for: .fast)
        let manager = makePrivacyManager(modelManager: modelManager)

        let result = try manager.deleteAllLocalData()

        XCTAssertEqual(result.settings, .default)
        XCTAssertEqual(result.customReplacementCount, 1)
        XCTAssertEqual(result.installedModelCount, 1)
        XCTAssertEqual(AppSettingsStore(defaults: defaults).load(), .default)
        XCTAssertNil(defaults.object(forKey: "shortcutOption"))
        XCTAssertNil(defaults.object(forKey: "cleanupMode"))
        XCTAssertNil(defaults.object(forKey: "selectedModelTier"))
        XCTAssertNil(defaults.object(forKey: "storeHistory"))
        XCTAssertNil(defaults.object(forKey: "hasCompletedOnboarding"))
        XCTAssertTrue(DictionaryEngine(userDefaults: defaults).listCustomReplacements().isEmpty)
        XCTAssertFalse(modelManager.metadata(for: .fast).isInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanCacheFile.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil),
            []
        )
    }

    func testDeleteAllLocalDataFailsBeforeClearingSettingsWhenModelReferenceIsOutsideCacheRoot() async throws {
        var settings = AppSettings.default
        settings.cleanupMode = .email
        settings.hasCompletedOnboarding = true
        AppSettingsStore(defaults: defaults).save(settings)
        DictionaryEngine(userDefaults: defaults).addReplacement(
            heardPhrase: "live kit",
            preferredReplacement: "LiveKit"
        )
        let orphanCacheFile = tempRoot.appendingPathComponent("orphan.bin")
        FileManager.default.createFile(atPath: orphanCacheFile.path, contents: Data([1, 2, 3]))
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-privacy-outside-model-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideRoot) }
        let modelManager = makeModelManager { _, _, _ in outsideRoot }
        try await modelManager.downloadModel(for: .accurate)
        let manager = makePrivacyManager(modelManager: modelManager)

        XCTAssertThrowsError(try manager.deleteAllLocalData()) { error in
            XCTAssertEqual(
                error as? ModelManager.ModelManagerError,
                .savedPathOutsideCacheRoot(outsideRoot)
            )
        }
        XCTAssertEqual(AppSettingsStore(defaults: defaults).load().cleanupMode, .email)
        XCTAssertFalse(DictionaryEngine(userDefaults: defaults).listCustomReplacements().isEmpty)
        XCTAssertTrue(modelManager.metadata(for: .accurate).isInstalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanCacheFile.path))
    }

    private func makePrivacyManager(
        modelManager: ModelManager? = nil,
        permissionSnapshot: PermissionSnapshot = PermissionSnapshot(statuses: [])
    ) -> PrivacyManager {
        PrivacyManager(
            settingsStore: AppSettingsStore(defaults: defaults),
            dictionaryEngine: DictionaryEngine(userDefaults: defaults),
            modelManager: modelManager ?? makeModelManager(),
            permissionSnapshotProvider: { permissionSnapshot },
            settingsLocation: "Test UserDefaults \(suiteName!)"
        )
    }

    private func makeModelManager(
        downloader: @escaping ModelManager.Downloader = { _, _, _ in
            XCTFail("Unexpected download in privacy manager test.")
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
