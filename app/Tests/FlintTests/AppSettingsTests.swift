import XCTest
@testable import Flint

final class AppSettingsTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "FlintTests.AppSettings.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testDefaultsCoverAllFields() {
        let store = AppSettingsStore(defaults: defaults)
        let settings = store.load()

        XCTAssertEqual(settings.shortcutSettings, .default)
        XCTAssertEqual(settings.cleanupMode, .clean)
        XCTAssertEqual(settings.selectedModelTier, .balanced)
        XCTAssertEqual(settings.insertionTargetBehavior, .recordingStart)
        XCTAssertEqual(settings.language, "auto")
        XCTAssertFalse(settings.launchAtLogin)
        XCTAssertTrue(settings.showOverlay)
        XCTAssertFalse(settings.playStartSound)
        XCTAssertFalse(settings.playStopSound)
        XCTAssertFalse(settings.storeHistory)
        XCTAssertFalse(settings.appAwareModesEnabled)
        XCTAssertTrue(settings.autoInsert)
        XCTAssertFalse(settings.hasCompletedOnboarding)
        XCTAssertTrue(settings.removeFillerWords)
        XCTAssertTrue(settings.addTerminalPunctuation)
        XCTAssertFalse(store.hasPersistedSelectedModelTier)
    }

    func testSelectedModelTierReportsWhenItHasBeenPersisted() {
        let store = AppSettingsStore(defaults: defaults)

        store.saveSelectedModelTier(.accurate)

        XCTAssertTrue(store.hasPersistedSelectedModelTier)
    }

    func testRoundTripPersistsAllFields() {
        let store = AppSettingsStore(defaults: defaults)
        let settings = AppSettings(
            shortcutSettings: ShortcutSettings(option: .commandShiftSpace, behavior: .toggle),
            cleanupMode: .email,
            selectedModelTier: .accurate,
            insertionTargetBehavior: .transcriptionFinish,
            language: "en",
            launchAtLogin: true,
            showOverlay: false,
            playStartSound: true,
            playStopSound: true,
            storeHistory: true,
            appAwareModesEnabled: true,
            autoInsert: false,
            hasCompletedOnboarding: true,
            removeFillerWords: false,
            addTerminalPunctuation: false
        )

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testStoreHistoryCanBeToggledIndependentlyAndDefaultsOff() {
        let store = AppSettingsStore(defaults: defaults)

        XCTAssertFalse(store.load().storeHistory)

        store.saveStoreHistory(true)
        XCTAssertTrue(store.load().storeHistory)

        store.saveStoreHistory(false)
        XCTAssertFalse(store.load().storeHistory)
    }

    func testStartupAndDeliveryPreferencesPersistIndependently() {
        let store = AppSettingsStore(defaults: defaults)

        store.saveLaunchAtLogin(true)
        store.saveAutoInsert(false)

        XCTAssertTrue(store.load().launchAtLogin)
        XCTAssertFalse(store.load().autoInsert)
    }

    func testAppAwareModesCanBeToggledIndependentlyAndDefaultsOff() {
        let store = AppSettingsStore(defaults: defaults)

        XCTAssertFalse(store.load().appAwareModesEnabled)

        store.saveAppAwareModesEnabled(true)
        XCTAssertTrue(store.load().appAwareModesEnabled)

        store.saveAppAwareModesEnabled(false)
        XCTAssertFalse(store.load().appAwareModesEnabled)
    }

    func testCorruptEnumBackedFieldsFallBackToSafeDefaults() {
        defaults.set("unknown-shortcut", forKey: "shortcutOption")
        defaults.set("unknown-behavior", forKey: "shortcutInputBehavior")
        defaults.set("unknown-cleanup", forKey: "cleanupMode")
        defaults.set("unknown-model", forKey: "selectedModelTier")
        defaults.set("unknown-target", forKey: "insertionTargetBehavior")

        let settings = AppSettingsStore(defaults: defaults).load()

        XCTAssertEqual(settings.shortcutSettings, .default)
        XCTAssertEqual(settings.cleanupMode, .clean)
        XCTAssertEqual(settings.selectedModelTier, .balanced)
        XCTAssertEqual(settings.insertionTargetBehavior, .recordingStart)
    }

    func testReadsExistingPersistedSelectionKeys() {
        defaults.set(ShortcutOption.controlSpace.rawValue, forKey: "shortcutOption")
        defaults.set(ShortcutInputBehavior.toggle.rawValue, forKey: "shortcutInputBehavior")
        defaults.set(CleanupMode.message.rawValue, forKey: "cleanupMode")
        defaults.set(ModelTier.fast.rawValue, forKey: "selectedModelTier")
        defaults.set(InsertionTargetBehavior.transcriptionFinish.rawValue, forKey: "insertionTargetBehavior")

        let settings = AppSettingsStore(defaults: defaults).load()

        XCTAssertEqual(settings.shortcutSettings, ShortcutSettings(option: .controlSpace, behavior: .toggle))
        XCTAssertEqual(settings.cleanupMode, .message)
        XCTAssertEqual(settings.selectedModelTier, .fast)
        XCTAssertEqual(settings.insertionTargetBehavior, .transcriptionFinish)
    }

    func testResetToDefaultsOverwritesPersistedValues() {
        let store = AppSettingsStore(defaults: defaults)
        store.save(AppSettings(
            shortcutSettings: ShortcutSettings(option: .commandShiftSpace, behavior: .toggle),
            cleanupMode: .email,
            selectedModelTier: .accurate,
            insertionTargetBehavior: .transcriptionFinish,
            language: "en",
            launchAtLogin: true,
            showOverlay: false,
            playStartSound: true,
            playStopSound: true,
            storeHistory: true,
            appAwareModesEnabled: true,
            autoInsert: false,
            hasCompletedOnboarding: true
        ))

        store.resetToDefaults()

        XCTAssertEqual(store.load(), .default)
    }

    func testRemovePersistedSettingsDeletesStoredValues() {
        let store = AppSettingsStore(defaults: defaults)
        store.save(AppSettings(
            shortcutSettings: ShortcutSettings(option: .commandShiftSpace, behavior: .toggle),
            cleanupMode: .email,
            selectedModelTier: .accurate,
            insertionTargetBehavior: .transcriptionFinish,
            language: "en",
            launchAtLogin: true,
            showOverlay: false,
            playStartSound: true,
            playStopSound: true,
            storeHistory: true,
            appAwareModesEnabled: true,
            autoInsert: false,
            hasCompletedOnboarding: true
        ))

        store.removePersistedSettings()

        XCTAssertNil(defaults.object(forKey: "shortcutOption"))
        XCTAssertNil(defaults.object(forKey: "shortcutInputBehavior"))
        XCTAssertNil(defaults.object(forKey: "cleanupMode"))
        XCTAssertNil(defaults.object(forKey: "selectedModelTier"))
        XCTAssertNil(defaults.object(forKey: "insertionTargetBehavior"))
        XCTAssertNil(defaults.object(forKey: "language"))
        XCTAssertNil(defaults.object(forKey: "launchAtLogin"))
        XCTAssertNil(defaults.object(forKey: "showOverlay"))
        XCTAssertNil(defaults.object(forKey: "playStartSound"))
        XCTAssertNil(defaults.object(forKey: "playStopSound"))
        XCTAssertNil(defaults.object(forKey: "storeHistory"))
        XCTAssertNil(defaults.object(forKey: "appAwareModesEnabled"))
        XCTAssertNil(defaults.object(forKey: "autoInsert"))
        XCTAssertNil(defaults.object(forKey: "hasCompletedOnboarding"))
        XCTAssertNil(defaults.object(forKey: "removeFillerWords"))
        XCTAssertNil(defaults.object(forKey: "addTerminalPunctuation"))
        XCTAssertEqual(store.load(), .default)
    }

    func testFormattingPreferencesPersistIndependentlyAndDefaultOn() {
        let store = AppSettingsStore(defaults: defaults)
        XCTAssertTrue(store.load().removeFillerWords)
        XCTAssertTrue(store.load().addTerminalPunctuation)

        store.saveRemoveFillerWords(false)
        store.saveAddTerminalPunctuation(false)

        XCTAssertFalse(store.load().removeFillerWords)
        XCTAssertFalse(store.load().addTerminalPunctuation)
    }
}
