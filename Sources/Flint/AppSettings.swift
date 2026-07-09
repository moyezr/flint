import Foundation

struct AppSettings: Equatable {
    var shortcutSettings: ShortcutSettings
    var cleanupMode: CleanupMode
    var selectedModelTier: ModelTier
    var insertionTargetBehavior: InsertionTargetBehavior
    var language: String
    var launchAtLogin: Bool
    var showOverlay: Bool
    var playStartSound: Bool
    var playStopSound: Bool
    var storeHistory: Bool
    var autoInsert: Bool
    var hasCompletedOnboarding: Bool

    static let `default` = AppSettings(
        shortcutSettings: .default,
        cleanupMode: .clean,
        selectedModelTier: .balanced,
        insertionTargetBehavior: .recordingStart,
        language: "auto",
        launchAtLogin: false,
        showOverlay: true,
        playStartSound: false,
        playStopSound: false,
        storeHistory: false,
        autoInsert: true,
        hasCompletedOnboarding: false
    )
}

struct AppSettingsStore {
    let defaults: UserDefaults

    private enum Key {
        static let shortcutOption = "shortcutOption"
        static let shortcutInputBehavior = "shortcutInputBehavior"
        static let cleanupMode = "cleanupMode"
        static let selectedModelTier = "selectedModelTier"
        static let insertionTargetBehavior = "insertionTargetBehavior"
        static let language = "language"
        static let launchAtLogin = "launchAtLogin"
        static let showOverlay = "showOverlay"
        static let playStartSound = "playStartSound"
        static let playStopSound = "playStopSound"
        static let storeHistory = "storeHistory"
        static let autoInsert = "autoInsert"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> AppSettings {
        AppSettings(
            shortcutSettings: ShortcutSettingsStore(
                defaults: defaults,
                shortcutKey: Key.shortcutOption,
                behaviorKey: Key.shortcutInputBehavior
            ).load(),
            cleanupMode: CleanupModeSelectionStore(defaults: defaults, key: Key.cleanupMode).load(),
            selectedModelTier: ModelTier(rawValue: defaults.string(forKey: Key.selectedModelTier) ?? "")
                ?? AppSettings.default.selectedModelTier,
            insertionTargetBehavior: InsertionTargetBehaviorStore(defaults: defaults, key: Key.insertionTargetBehavior).load(),
            language: defaults.string(forKey: Key.language) ?? AppSettings.default.language,
            launchAtLogin: bool(forKey: Key.launchAtLogin, defaultValue: AppSettings.default.launchAtLogin),
            showOverlay: bool(forKey: Key.showOverlay, defaultValue: AppSettings.default.showOverlay),
            playStartSound: bool(forKey: Key.playStartSound, defaultValue: AppSettings.default.playStartSound),
            playStopSound: bool(forKey: Key.playStopSound, defaultValue: AppSettings.default.playStopSound),
            storeHistory: bool(forKey: Key.storeHistory, defaultValue: AppSettings.default.storeHistory),
            autoInsert: bool(forKey: Key.autoInsert, defaultValue: AppSettings.default.autoInsert),
            hasCompletedOnboarding: bool(
                forKey: Key.hasCompletedOnboarding,
                defaultValue: AppSettings.default.hasCompletedOnboarding
            )
        )
    }

    func save(_ settings: AppSettings) {
        saveShortcutSettings(settings.shortcutSettings)
        saveCleanupMode(settings.cleanupMode)
        saveSelectedModelTier(settings.selectedModelTier)
        saveInsertionTargetBehavior(settings.insertionTargetBehavior)
        defaults.set(settings.language, forKey: Key.language)
        defaults.set(settings.launchAtLogin, forKey: Key.launchAtLogin)
        defaults.set(settings.showOverlay, forKey: Key.showOverlay)
        defaults.set(settings.playStartSound, forKey: Key.playStartSound)
        defaults.set(settings.playStopSound, forKey: Key.playStopSound)
        defaults.set(settings.storeHistory, forKey: Key.storeHistory)
        defaults.set(settings.autoInsert, forKey: Key.autoInsert)
        defaults.set(settings.hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
    }

    func saveShortcutSettings(_ settings: ShortcutSettings) {
        ShortcutSettingsStore(
            defaults: defaults,
            shortcutKey: Key.shortcutOption,
            behaviorKey: Key.shortcutInputBehavior
        ).save(settings)
    }

    func saveCleanupMode(_ mode: CleanupMode) {
        CleanupModeSelectionStore(defaults: defaults, key: Key.cleanupMode).save(mode)
    }

    func saveSelectedModelTier(_ tier: ModelTier) {
        defaults.set(tier.rawValue, forKey: Key.selectedModelTier)
    }

    func saveInsertionTargetBehavior(_ behavior: InsertionTargetBehavior) {
        InsertionTargetBehaviorStore(defaults: defaults, key: Key.insertionTargetBehavior).save(behavior)
    }

    func saveHasCompletedOnboarding(_ hasCompletedOnboarding: Bool) {
        defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
    }

    private func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }
}
