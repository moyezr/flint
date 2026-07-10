import XCTest
@testable import Flint

@MainActor
final class SettingsModelTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "FlintTests.SettingsModel.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-settings-model-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        tempRoot = nil
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testPreferenceChangesPersistAndNotify() {
        var receivedSettings: [AppSettings] = []
        let model = makeModel { receivedSettings.append($0) }

        model.setShortcutOption(.controlSpace)
        model.setShortcutInputBehavior(.toggle)
        model.setCleanupMode(.email)
        model.setInsertionTargetBehavior(.transcriptionFinish)

        let persisted = AppSettingsStore(defaults: defaults).load()
        XCTAssertEqual(persisted.shortcutSettings, ShortcutSettings(option: .controlSpace, behavior: .toggle))
        XCTAssertEqual(persisted.cleanupMode, .email)
        XCTAssertEqual(persisted.insertionTargetBehavior, .transcriptionFinish)
        XCTAssertEqual(receivedSettings.count, 4)
        XCTAssertEqual(receivedSettings.last?.insertionTargetBehavior, .transcriptionFinish)
        XCTAssertEqual(model.statusMessage, "Insertion target saved.")
        XCTAssertTrue(model.errorMessage.isEmpty)
    }

    func testShortcutEditsMergeWithChangesMadeWhileSettingsIsOpen() {
        let store = AppSettingsStore(defaults: defaults)
        let model = makeModel()

        store.saveShortcutSettings(ShortcutSettings(option: .controlSpace, behavior: .pushToTalk))
        model.setShortcutInputBehavior(.toggle)

        XCTAssertEqual(store.load().shortcutSettings, ShortcutSettings(option: .controlSpace, behavior: .toggle))

        store.saveShortcutSettings(ShortcutSettings(option: .commandShiftSpace, behavior: .pushToTalk))
        model.setShortcutOption(.rightOption)

        XCTAssertEqual(store.load().shortcutSettings, ShortcutSettings(option: .rightOption, behavior: .pushToTalk))
    }

    func testAppAwareTogglePersistsNotifiesAndOpensAppModes() {
        var receivedSettings: [AppSettings] = []
        var showAppModesCount = 0
        let model = makeModel(
            onSettingsChanged: { receivedSettings.append($0) },
            onShowAppModes: { showAppModesCount += 1 }
        )

        model.setAppAwareModesEnabled(true)
        model.showAppModes()

        XCTAssertTrue(AppSettingsStore(defaults: defaults).load().appAwareModesEnabled)
        XCTAssertTrue(model.settings.appAwareModesEnabled)
        XCTAssertEqual(receivedSettings.last?.appAwareModesEnabled, true)
        XCTAssertEqual(showAppModesCount, 1)
    }

    func testModelSelectionAndFakeDownloadDeleteLifecycle() async throws {
        var requestedVariants: [String] = []
        var receivedSettings: [AppSettings] = []
        var modelMetadataChangeCount = 0
        let model = makeModel(
            onSettingsChanged: { receivedSettings.append($0) },
            onModelMetadataChanged: { modelMetadataChangeCount += 1 },
            downloader: { variant, downloadBase, _ in
                requestedVariants.append(variant)
                let folder = downloadBase!.appendingPathComponent("downloaded-\(variant)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                return folder
            }
        )

        model.setSelectedModelTier(.fast)

        XCTAssertEqual(defaults.string(forKey: "selectedModelTier"), ModelTier.fast.rawValue)
        XCTAssertEqual(model.settings.selectedModelTier, .fast)
        XCTAssertEqual(receivedSettings.last?.selectedModelTier, .fast)
        XCTAssertFalse(try XCTUnwrap(model.metadata(for: .fast)).isInstalled)

        await model.downloadSelectedModel()

        XCTAssertEqual(requestedVariants, ["tiny"])
        let downloaded = try XCTUnwrap(model.metadata(for: .fast))
        XCTAssertTrue(downloaded.isInstalled)
        XCTAssertEqual(downloaded.installedFolder?.lastPathComponent, "downloaded-tiny")
        XCTAssertEqual(model.statusMessage, "Fast model is ready.")
        XCTAssertTrue(model.errorMessage.isEmpty)
        XCTAssertEqual(modelMetadataChangeCount, 1)

        model.deleteSelectedModel()

        XCTAssertFalse(try XCTUnwrap(model.metadata(for: .fast)).isInstalled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloaded.installedFolder!.path))
        XCTAssertEqual(model.statusMessage, "Fast model deleted.")
        XCTAssertEqual(modelMetadataChangeCount, 2)
    }

    func testVocabularyAddAndDeleteUsesDictionaryEngineStorage() throws {
        let model = makeModel()
        model.newHeardPhrase = " api "
        model.newPreferredReplacement = " API "

        model.addVocabularyReplacement()

        let storedReplacement = try XCTUnwrap(DictionaryEngine(userDefaults: defaults).listCustomReplacements().first)
        XCTAssertEqual(storedReplacement.heardPhrase, "api")
        XCTAssertEqual(storedReplacement.preferredReplacement, "API")
        XCTAssertEqual(model.customReplacements, [storedReplacement])
        XCTAssertEqual(model.statusMessage, "Vocabulary item added.")

        model.deleteVocabularyReplacement(storedReplacement)

        XCTAssertTrue(DictionaryEngine(userDefaults: defaults).listCustomReplacements().isEmpty)
        XCTAssertTrue(model.customReplacements.isEmpty)
        XCTAssertEqual(model.statusMessage, "Vocabulary item deleted.")
    }

    func testHistoryTogglePersistsNotifiesAndOpensPrivacy() {
        var receivedSettings: [AppSettings] = []
        var showPrivacyCount = 0
        let model = makeModel(
            onSettingsChanged: { receivedSettings.append($0) },
            onShowPrivacy: { showPrivacyCount += 1 }
        )

        model.setStoreHistory(true)
        model.showPrivacy()

        XCTAssertTrue(AppSettingsStore(defaults: defaults).load().storeHistory)
        XCTAssertTrue(model.settings.storeHistory)
        XCTAssertEqual(receivedSettings.last?.storeHistory, true)
        XCTAssertEqual(showPrivacyCount, 1)
    }

    private func makeModel(
        onSettingsChanged: @escaping (AppSettings) -> Void = { _ in },
        onModelMetadataChanged: @escaping () -> Void = {},
        onShowAppModes: @escaping () -> Void = {},
        onShowPrivacy: @escaping () -> Void = {},
        downloader: @escaping ModelManager.Downloader = { _, _, _ in
            XCTFail("Unexpected production-style download in unit test.")
            return URL(fileURLWithPath: "/unexpected", isDirectory: true)
        }
    ) -> SettingsModel {
        SettingsModel(
            settingsStore: AppSettingsStore(defaults: defaults),
            modelManager: ModelManager(
                defaults: defaults,
                modelCacheRoot: tempRoot,
                downloader: downloader
            ),
            dictionaryEngine: DictionaryEngine(userDefaults: defaults),
            onSettingsChanged: onSettingsChanged,
            onModelMetadataChanged: onModelMetadataChanged,
            onShowAppModes: onShowAppModes,
            onShowPrivacy: onShowPrivacy
        )
    }
}
