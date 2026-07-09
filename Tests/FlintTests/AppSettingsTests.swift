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
        let settings = AppSettingsStore(defaults: defaults).load()

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
        XCTAssertTrue(settings.autoInsert)
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
            autoInsert: false
        )

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
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
}
