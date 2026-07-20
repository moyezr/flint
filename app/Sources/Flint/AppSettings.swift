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
    var appAwareModesEnabled: Bool
    var autoInsert: Bool
    var hasCompletedOnboarding: Bool
    var removeFillerWords: Bool
    var addTerminalPunctuation: Bool

    init(
        shortcutSettings: ShortcutSettings,
        cleanupMode: CleanupMode,
        selectedModelTier: ModelTier,
        insertionTargetBehavior: InsertionTargetBehavior,
        language: String,
        launchAtLogin: Bool,
        showOverlay: Bool,
        playStartSound: Bool,
        playStopSound: Bool,
        storeHistory: Bool,
        appAwareModesEnabled: Bool,
        autoInsert: Bool,
        hasCompletedOnboarding: Bool,
        removeFillerWords: Bool = true,
        addTerminalPunctuation: Bool = true
    ) {
        self.shortcutSettings = shortcutSettings
        self.cleanupMode = cleanupMode
        self.selectedModelTier = selectedModelTier
        self.insertionTargetBehavior = insertionTargetBehavior
        self.language = language
        self.launchAtLogin = launchAtLogin
        self.showOverlay = showOverlay
        self.playStartSound = playStartSound
        self.playStopSound = playStopSound
        self.storeHistory = storeHistory
        self.appAwareModesEnabled = appAwareModesEnabled
        self.autoInsert = autoInsert
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.removeFillerWords = removeFillerWords
        self.addTerminalPunctuation = addTerminalPunctuation
    }

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
        appAwareModesEnabled: false,
        autoInsert: true,
        hasCompletedOnboarding: false,
        removeFillerWords: true,
        addTerminalPunctuation: true
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
        static let appAwareModesEnabled = "appAwareModesEnabled"
        static let autoInsert = "autoInsert"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let removeFillerWords = "removeFillerWords"
        static let addTerminalPunctuation = "addTerminalPunctuation"
        static let updateLastSuccessfulCheck = "updateLastSuccessfulCheck"
        static let updateLastNotifiedVersion = "updateLastNotifiedVersion"

        static let all = [
            shortcutOption,
            shortcutInputBehavior,
            cleanupMode,
            selectedModelTier,
            insertionTargetBehavior,
            language,
            launchAtLogin,
            showOverlay,
            playStartSound,
            playStopSound,
            storeHistory,
            appAwareModesEnabled,
            autoInsert,
            hasCompletedOnboarding,
            removeFillerWords,
            addTerminalPunctuation,
            updateLastSuccessfulCheck,
            updateLastNotifiedVersion
        ]
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
            appAwareModesEnabled: bool(
                forKey: Key.appAwareModesEnabled,
                defaultValue: AppSettings.default.appAwareModesEnabled
            ),
            autoInsert: bool(forKey: Key.autoInsert, defaultValue: AppSettings.default.autoInsert),
            hasCompletedOnboarding: bool(
                forKey: Key.hasCompletedOnboarding,
                defaultValue: AppSettings.default.hasCompletedOnboarding
            ),
            removeFillerWords: bool(
                forKey: Key.removeFillerWords,
                defaultValue: AppSettings.default.removeFillerWords
            ),
            addTerminalPunctuation: bool(
                forKey: Key.addTerminalPunctuation,
                defaultValue: AppSettings.default.addTerminalPunctuation
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
        defaults.set(settings.appAwareModesEnabled, forKey: Key.appAwareModesEnabled)
        defaults.set(settings.autoInsert, forKey: Key.autoInsert)
        defaults.set(settings.hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding)
        defaults.set(settings.removeFillerWords, forKey: Key.removeFillerWords)
        defaults.set(settings.addTerminalPunctuation, forKey: Key.addTerminalPunctuation)
    }

    func resetToDefaults() {
        save(.default)
    }

    func removePersistedSettings() {
        for key in Key.all {
            defaults.removeObject(forKey: key)
        }
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

    func saveStoreHistory(_ storeHistory: Bool) {
        defaults.set(storeHistory, forKey: Key.storeHistory)
    }

    func saveLaunchAtLogin(_ launchAtLogin: Bool) {
        defaults.set(launchAtLogin, forKey: Key.launchAtLogin)
    }

    func saveAutoInsert(_ autoInsert: Bool) {
        defaults.set(autoInsert, forKey: Key.autoInsert)
    }

    func savePlayStartSound(_ playStartSound: Bool) {
        defaults.set(playStartSound, forKey: Key.playStartSound)
    }

    func savePlayStopSound(_ playStopSound: Bool) {
        defaults.set(playStopSound, forKey: Key.playStopSound)
    }

    func saveAppAwareModesEnabled(_ appAwareModesEnabled: Bool) {
        defaults.set(appAwareModesEnabled, forKey: Key.appAwareModesEnabled)
    }

    func saveRemoveFillerWords(_ removeFillerWords: Bool) {
        defaults.set(removeFillerWords, forKey: Key.removeFillerWords)
    }

    func saveAddTerminalPunctuation(_ addTerminalPunctuation: Bool) {
        defaults.set(addTerminalPunctuation, forKey: Key.addTerminalPunctuation)
    }

    private func bool(forKey key: String, defaultValue: Bool) -> Bool {
        guard defaults.object(forKey: key) != nil else {
            return defaultValue
        }
        return defaults.bool(forKey: key)
    }
}
