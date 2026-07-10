import XCTest
@testable import Flint

final class PrivacyManagerTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempRoot: URL!
    private var licenseManager: LicenseManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "FlintTests.PrivacyManager.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-privacy-manager-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        licenseManager = LicenseManager(
            service: "com.flint.tests.privacy.license.\(UUID().uuidString)",
            account: "local-activation"
        )
        try licenseManager.clear()
    }

    override func tearDownWithError() throws {
        try? licenseManager?.clear()
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        tempRoot = nil
        licenseManager = nil
        try super.tearDownWithError()
    }

    func testSnapshotShowsPlainPrivacyRowsPathsAndHistoryStatus() throws {
        var settings = AppSettings.default
        settings.storeHistory = true
        settings.appAwareModesEnabled = true
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
        let historyStore = try HistoryStore(databaseURL: historyDatabaseURL)
        _ = try historyStore.insert(makeHistoryEntry())
        _ = try AppModeRuleStore(databaseURL: historyDatabaseURL).create(NewAppModeRule(
            appBundleID: "com.apple.mail",
            mode: .email
        ))

        let snapshot = manager.snapshot()

        XCTAssertEqual(snapshot.statusRows.first { $0.id == "transcription" }?.value, "Local")
        XCTAssertEqual(snapshot.statusRows.first { $0.id == "history" }?.value, "On")
        XCTAssertEqual(snapshot.statusRows.first { $0.id == "app-modes" }?.value, "On")
        XCTAssertTrue(snapshot.statusRows.first { $0.id == "app-modes" }?.detail.contains("1 enabled bundle-ID") == true)
        XCTAssertTrue(snapshot.statusRows.first { $0.id == "history" }?.detail.contains("1 entries") == true)
        XCTAssertEqual(snapshot.statusRows.first { $0.id == "telemetry" }?.detail, "Telemetry is not implemented.")
        XCTAssertEqual(snapshot.permissionStatuses.map(\.kind), [.microphone, .accessibility, .inputMonitoring])
        XCTAssertEqual(snapshot.dataLocations.first { $0.id == "settings" }?.path, "Test UserDefaults \(suiteName!)")
        XCTAssertEqual(snapshot.dataLocations.first { $0.id == "vocabulary" }?.path, "Test UserDefaults \(suiteName!)")
        XCTAssertEqual(snapshot.dataLocations.first { $0.id == "model-cache" }?.path, tempRoot.path)
        XCTAssertEqual(snapshot.dataLocations.first { $0.id == "history" }?.path, historyDatabaseURL.path)
        XCTAssertEqual(snapshot.dataLocations.first { $0.id == "history" }?.detail, "1 history entries. Audio files and blobs are never stored.")
        XCTAssertEqual(snapshot.dataLocations.first { $0.id == "app-mode-rules" }?.path, historyDatabaseURL.path)
        XCTAssertTrue(snapshot.dataLocations.first { $0.id == "app-mode-rules" }?.detail.contains("1 app-specific") == true)
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
        let historyStore = try HistoryStore(databaseURL: historyDatabaseURL)
        _ = try historyStore.insert(makeHistoryEntry())
        _ = try AppModeRuleStore(databaseURL: historyDatabaseURL).create(NewAppModeRule(
            appBundleID: "com.apple.mail",
            mode: .email
        ))
        let walURL = URL(fileURLWithPath: historyDatabaseURL.path + "-wal")
        let shmURL = URL(fileURLWithPath: historyDatabaseURL.path + "-shm")
        FileManager.default.createFile(atPath: walURL.path, contents: Data([4]))
        FileManager.default.createFile(atPath: shmURL.path, contents: Data([5]))

        let result = try manager.deleteAllLocalData()

        XCTAssertEqual(result.settings, .default)
        XCTAssertEqual(result.customReplacementCount, 1)
        XCTAssertEqual(result.installedModelCount, 1)
        XCTAssertEqual(result.historyEntryCount, 1)
        XCTAssertEqual(result.appModeRuleCount, 1)
        XCTAssertEqual(AppSettingsStore(defaults: defaults).load(), .default)
        XCTAssertNil(defaults.object(forKey: "shortcutOption"))
        XCTAssertNil(defaults.object(forKey: "cleanupMode"))
        XCTAssertNil(defaults.object(forKey: "selectedModelTier"))
        XCTAssertNil(defaults.object(forKey: "storeHistory"))
        XCTAssertNil(defaults.object(forKey: "hasCompletedOnboarding"))
        XCTAssertTrue(DictionaryEngine(userDefaults: defaults).listCustomReplacements().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyDatabaseURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: walURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: shmURL.path))
        XCTAssertEqual(try HistoryStore(databaseURL: historyDatabaseURL).count(), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyDatabaseURL.path))
        XCTAssertFalse(modelManager.metadata(for: .fast).isInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanCacheFile.path))
        let nonHistoryFiles = try FileManager.default
            .contentsOfDirectory(at: tempRoot, includingPropertiesForKeys: nil)
            .filter { !$0.lastPathComponent.hasPrefix("History.sqlite") }
        XCTAssertEqual(nonHistoryFiles, [])
    }

    func testDeleteAllLocalDataClearsLicenseState() throws {
        try licenseManager.saveActivatedLicense(
            licenseKey: "FLINT-PRIVACY-KEY",
            activationID: "act_privacy",
            activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let manager = makePrivacyManager()

        try manager.deleteAllLocalData()

        XCTAssertEqual(try licenseManager.load(), .inactive)
    }

    func testDeleteAllLocalDataFailsBeforeClearingAnythingWhenLicenseClearFails() async throws {
        var settings = AppSettings.default
        settings.cleanupMode = .email
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
        let historyStore = try HistoryStore(databaseURL: historyDatabaseURL)
        _ = try historyStore.insert(makeHistoryEntry())
        let failingLicenseManager = LicenseManager(
            service: "com.flint.tests.privacy.failing-license.\(UUID().uuidString)",
            account: "local-activation",
            keychain: LicenseKeychainClient(
                copyMatching: { _, _ in errSecItemNotFound },
                update: { _, _ in errSecItemNotFound },
                add: { _, _ in errSecSuccess },
                delete: { _ in errSecAuthFailed }
            )
        )
        let manager = makePrivacyManager(
            modelManager: modelManager,
            licenseManager: failingLicenseManager
        )

        XCTAssertThrowsError(try manager.deleteAllLocalData()) { error in
            XCTAssertEqual(
                error as? LicenseManager.LicenseManagerError,
                .keychainFailure(operation: "delete", status: errSecAuthFailed)
            )
        }
        XCTAssertEqual(AppSettingsStore(defaults: defaults).load().cleanupMode, .email)
        XCTAssertFalse(DictionaryEngine(userDefaults: defaults).listCustomReplacements().isEmpty)
        XCTAssertTrue(modelManager.metadata(for: .fast).isInstalled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphanCacheFile.path))
        XCTAssertEqual(try historyStore.count(), 1)
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
        let historyStore = try HistoryStore(databaseURL: historyDatabaseURL)
        _ = try historyStore.insert(makeHistoryEntry())
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
        XCTAssertEqual(try historyStore.count(), 1)
    }

    private func makePrivacyManager(
        modelManager: ModelManager? = nil,
        licenseManager: LicenseManager? = nil,
        permissionSnapshot: PermissionSnapshot = PermissionSnapshot(statuses: [])
    ) -> PrivacyManager {
        PrivacyManager(
            settingsStore: AppSettingsStore(defaults: defaults),
            dictionaryEngine: DictionaryEngine(userDefaults: defaults),
            modelManager: modelManager ?? makeModelManager(),
            historyStore: try! HistoryStore(databaseURL: historyDatabaseURL),
            appModeRuleStore: AppModeRuleStore(databaseURL: historyDatabaseURL),
            licenseManager: licenseManager ?? self.licenseManager,
            permissionSnapshotProvider: { permissionSnapshot },
            settingsLocation: "Test UserDefaults \(suiteName!)"
        )
    }

    private var historyDatabaseURL: URL {
        tempRoot.appendingPathComponent("History.sqlite")
    }

    private func makeHistoryEntry() -> NewHistoryEntry {
        NewHistoryEntry(
            createdAt: Date(timeIntervalSince1970: 100),
            activeAppName: "Notes",
            activeAppBundleID: "com.apple.Notes",
            mode: CleanupMode.clean.rawValue,
            rawTranscript: "raw",
            finalText: "final",
            durationMS: 100,
            modelName: "base",
            language: "auto"
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
