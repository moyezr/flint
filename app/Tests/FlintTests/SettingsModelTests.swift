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
        var preparedTiers: [ModelTier] = []
        var receivedSettings: [AppSettings] = []
        var modelMetadataChangeCount = 0
        let model = makeModel(
            onSettingsChanged: { receivedSettings.append($0) },
            onModelMetadataChanged: { modelMetadataChangeCount += 1 },
            modelPreparationAction: { tier in preparedTiers.append(tier) },
            downloader: { variant, downloadBase, _ in
                requestedVariants.append(variant)
                let folder = downloadBase!.appendingPathComponent("downloaded-\(variant)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                _ = FileManager.default.createFile(
                    atPath: folder.appendingPathComponent("model.bin").path,
                    contents: Data([1])
                )
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
        XCTAssertEqual(preparedTiers, [.fast])
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

    func testVocabularyAddAndDeleteUsesLearningStore() async throws {
        let learningStore = LearningStore(databaseURL: tempRoot.appendingPathComponent("Learning.sqlite"))
        var publishedSnapshots: [MemorySnapshot] = []
        let model = makeModel(
            learningStore: learningStore,
            onLearningChanged: { publishedSnapshots.append($0) }
        )
        model.newHeardPhrase = " api "
        model.newPreferredReplacement = " API "

        await model.addVocabularyReplacement()

        let savedMemories = try await learningStore.listMemories()
        let storedReplacement = try XCTUnwrap(savedMemories.first)
        XCTAssertEqual(storedReplacement.heardForm, "api")
        XCTAssertEqual(storedReplacement.preferredForm, "API")
        XCTAssertEqual(model.customReplacements, [storedReplacement])
        XCTAssertEqual(model.statusMessage, "Vocabulary item added.")
        XCTAssertEqual(publishedSnapshots.last?.memories, [storedReplacement])

        await model.deleteVocabularyReplacement(storedReplacement)

        let remainingMemories = try await learningStore.listMemories()
        XCTAssertTrue(remainingMemories.isEmpty)
        XCTAssertTrue(model.customReplacements.isEmpty)
        XCTAssertEqual(model.statusMessage, "Vocabulary item deleted.")
        XCTAssertEqual(publishedSnapshots.last, .empty)
    }

    func testVocabularyApplicationScopeValidationAndConflictConfirmation() async throws {
        let learningStore = LearningStore(databaseURL: tempRoot.appendingPathComponent("Learning.sqlite"))
        let model = makeModel(learningStore: learningStore)
        model.newHeardPhrase = "flask"
        model.newPreferredReplacement = "Flask"
        model.newVocabularyScope = .application

        await model.addVocabularyReplacement()
        XCTAssertEqual(model.errorMessage, "Choose an application for an app-specific vocabulary item.")

        model.newVocabularyApplicationBundleID = "com.microsoft.VSCode"
        await model.addVocabularyReplacement()
        var memories = try await learningStore.listMemories()
        XCTAssertEqual(memories.count, 1)

        model.newHeardPhrase = "flask"
        model.newPreferredReplacement = "FLASK"
        await model.addVocabularyReplacement()
        XCTAssertNotNil(model.pendingVocabularyConflict)
        memories = try await learningStore.listMemories()
        XCTAssertEqual(memories.first?.preferredForm, "Flask")

        await model.addVocabularyReplacement(replaceExisting: true)
        XCTAssertNil(model.pendingVocabularyConflict)
        memories = try await learningStore.listMemories()
        XCTAssertEqual(memories.first?.preferredForm, "FLASK")
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

    func testFeedbackSoundTogglesPersistAndNotify() {
        var receivedSettings: [AppSettings] = []
        let model = makeModel(onSettingsChanged: { receivedSettings.append($0) })

        model.setPlayStartSound(true)
        model.setPlayStopSound(true)

        let persisted = AppSettingsStore(defaults: defaults).load()
        XCTAssertTrue(persisted.playStartSound)
        XCTAssertTrue(persisted.playStopSound)
        XCTAssertTrue(receivedSettings.last?.playStartSound ?? false)
        XCTAssertTrue(receivedSettings.last?.playStopSound ?? false)
    }

    func testFormattingTogglesPersistAndNotify() {
        var receivedSettings: [AppSettings] = []
        let model = makeModel(onSettingsChanged: { receivedSettings.append($0) })

        model.setRemoveFillerWords(false)
        model.setAddTerminalPunctuation(false)

        let persisted = AppSettingsStore(defaults: defaults).load()
        XCTAssertFalse(persisted.removeFillerWords)
        XCTAssertFalse(persisted.addTerminalPunctuation)
        XCTAssertFalse(receivedSettings.last?.removeFillerWords ?? true)
        XCTAssertFalse(receivedSettings.last?.addTerminalPunctuation ?? true)
    }

    private func makeModel(
        learningStore: LearningStore? = nil,
        onSettingsChanged: @escaping (AppSettings) -> Void = { _ in },
        onModelMetadataChanged: @escaping () -> Void = {},
        modelPreparationAction: @escaping (ModelTier) async throws -> Void = { _ in },
        onShowAppModes: @escaping () -> Void = {},
        onShowPrivacy: @escaping () -> Void = {},
        onLearningChanged: @escaping (MemorySnapshot) -> Void = { _ in },
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
            learningStore: learningStore,
            onSettingsChanged: onSettingsChanged,
            onModelMetadataChanged: onModelMetadataChanged,
            modelPreparationAction: modelPreparationAction,
            onShowAppModes: onShowAppModes,
            onShowPrivacy: onShowPrivacy,
            onLearningChanged: onLearningChanged,
            runningApplicationsProvider: { [] }
        )
    }
}
