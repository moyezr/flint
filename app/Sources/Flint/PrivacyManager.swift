import Foundation

struct PrivacyStatusRow: Equatable, Identifiable {
    let id: String
    let title: String
    let value: String
    let detail: String
}

struct PrivacyDataLocation: Equatable, Identifiable {
    let id: String
    let title: String
    let path: String
    let detail: String
}

struct PrivacyDashboardSnapshot: Equatable {
    let statusRows: [PrivacyStatusRow]
    let permissionStatuses: [PermissionStatus]
    let dataLocations: [PrivacyDataLocation]
}

struct PrivacyDeletionResult: Equatable {
    let settings: AppSettings
    let customReplacementCount: Int
    let installedModelCount: Int
    let historyEntryCount: Int
    let appModeRuleCount: Int
}

struct PrivacyManager {
    enum PrivacyManagerError: LocalizedError {
        case historyUnavailable

        var errorDescription: String? {
            switch self {
            case .historyUnavailable:
                return "History storage is unavailable."
            }
        }
    }

    private let settingsStore: AppSettingsStore
    private let dictionaryEngine: DictionaryEngine
    private let modelManager: ModelManager
    private let historyStore: HistoryStore?
    private let appModeRuleStore: AppModeRuleStore?
    private let licenseManager: LicenseManager
    private let permissionSnapshotProvider: () -> PermissionSnapshot
    private let settingsLocation: String

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        dictionaryEngine: DictionaryEngine = DictionaryEngine(),
        modelManager: ModelManager = ModelManager(),
        historyStore: HistoryStore? = try? HistoryStore(),
        appModeRuleStore: AppModeRuleStore? = AppModeRuleStore(),
        licenseManager: LicenseManager = LicenseManager(),
        permissionSnapshotProvider: @escaping () -> PermissionSnapshot = { PermissionManager().snapshot() },
        settingsLocation: String = PrivacyManager.defaultSettingsLocation()
    ) {
        self.settingsStore = settingsStore
        self.dictionaryEngine = dictionaryEngine
        self.modelManager = modelManager
        self.historyStore = historyStore
        self.appModeRuleStore = appModeRuleStore
        self.licenseManager = licenseManager
        self.permissionSnapshotProvider = permissionSnapshotProvider
        self.settingsLocation = settingsLocation
    }

    func snapshot() -> PrivacyDashboardSnapshot {
        let settings = settingsStore.load()
        let historyCount = (try? historyStore?.count()) ?? 0
        let appModeRules = (try? appModeRuleStore?.list()) ?? []
        let appModeRuleCount = appModeRules.count
        let activeBundleRuleCount = appModeRules.filter { $0.enabled && $0.appBundleID != nil }.count
        return PrivacyDashboardSnapshot(
            statusRows: [
                PrivacyStatusRow(
                    id: "transcription",
                    title: "Transcription",
                    value: "Local",
                    detail: "Audio is transcribed on this Mac. Transcript content is not sent to a server."
                ),
                PrivacyStatusRow(
                    id: "history",
                    title: "History",
                    value: settings.storeHistory ? "On" : "Off",
                    detail: settings.storeHistory
                        ? "Transcript history is enabled with \(historyCount) entries. Raw audio is not stored."
                        : "Transcript history is disabled. \(historyCount) entries are stored locally."
                ),
                PrivacyStatusRow(
                    id: "app-modes",
                    title: "App-Aware Modes",
                    value: settings.appAwareModesEnabled ? "On" : "Off",
                    detail: settings.appAwareModesEnabled
                        ? "\(activeBundleRuleCount) enabled bundle-ID rules can apply to matching apps. \(appModeRuleCount - activeBundleRuleCount) other rules are stored but inactive or unavailable."
                        : "\(appModeRuleCount) app-specific cleanup rules are stored but inactive."
                ),
                PrivacyStatusRow(
                    id: "telemetry",
                    title: "Telemetry",
                    value: "Off",
                    detail: "Telemetry is not implemented."
                )
            ],
            permissionStatuses: permissionSnapshotProvider().statuses,
            dataLocations: [
                PrivacyDataLocation(
                    id: "settings",
                    title: "Settings and Defaults",
                    path: settingsLocation,
                    detail: "Shortcut, mode, model selection, history, overlay, sound, and onboarding preferences."
                ),
                PrivacyDataLocation(
                    id: "vocabulary",
                    title: "Custom Vocabulary",
                    path: settingsLocation,
                    detail: "\(dictionaryEngine.listCustomReplacements().count) custom entries stored under UserDefaults key \(dictionaryEngine.customReplacementsStorageDescription)."
                ),
                PrivacyDataLocation(
                    id: "model-cache",
                    title: "Model Cache",
                    path: modelManager.modelCacheRoot.path,
                    detail: "\(modelManager.metadata().filter { $0.isInstalled }.count) installed model references."
                ),
                PrivacyDataLocation(
                    id: "history",
                    title: "History Database",
                    path: historyStore?.databaseURL.path ?? "Unavailable",
                    detail: "\(historyCount) history entries. Audio files and blobs are never stored."
                ),
                PrivacyDataLocation(
                    id: "app-mode-rules",
                    title: "App Mode Rules",
                    path: appModeRuleStore?.databaseURL.path ?? "Unavailable",
                    detail: "\(appModeRuleCount) app-specific cleanup rules. URL patterns are stored locally and are not used until URL detection exists."
                )
            ]
        )
    }

    func historyEntries(limit: Int = 50) throws -> [HistoryEntry] {
        guard let historyStore else {
            throw PrivacyManagerError.historyUnavailable
        }
        return try historyStore.list(limit: limit)
    }

    func historyCount() -> Int {
        (try? historyStore?.count()) ?? 0
    }

    func setHistoryEnabled(_ enabled: Bool) {
        settingsStore.saveStoreHistory(enabled)
    }

    func deleteHistoryEntry(id: Int64) throws {
        guard let historyStore else {
            throw PrivacyManagerError.historyUnavailable
        }
        try historyStore.delete(id: id)
    }

    func deleteAllHistory() throws {
        guard let historyStore else {
            throw PrivacyManagerError.historyUnavailable
        }
        try historyStore.deleteAll()
    }

    func exportHistory(to url: URL) throws {
        guard let historyStore else {
            throw PrivacyManagerError.historyUnavailable
        }
        try historyStore.export(to: url)
    }

    @discardableResult
    func deleteAllLocalData() throws -> PrivacyDeletionResult {
        let customReplacementCount = dictionaryEngine.listCustomReplacements().count
        let installedModelCount = modelManager.metadata().filter { $0.isInstalled }.count
        let historyEntryCount = (try? historyStore?.count()) ?? 0
        let appModeRuleCount = (try? appModeRuleStore?.list().count) ?? 0

        try licenseManager.clear()
        try modelManager.deleteAllCachedModelsAndReferences()
        let databaseURLs = Set([historyStore?.databaseURL, appModeRuleStore?.databaseURL].compactMap { $0 })
        for databaseURL in databaseURLs {
            try HistoryStore(databaseURL: databaseURL).deleteDatabaseFiles()
        }
        settingsStore.removePersistedSettings()
        dictionaryEngine.removeAllCustomReplacements()

        return PrivacyDeletionResult(
            settings: settingsStore.load(),
            customReplacementCount: customReplacementCount,
            installedModelCount: installedModelCount,
            historyEntryCount: historyEntryCount,
            appModeRuleCount: appModeRuleCount
        )
    }

    static func defaultSettingsLocation() -> String {
        let preferencesDirectory = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)

        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            return preferencesDirectory
                .appendingPathComponent("\(bundleIdentifier).plist")
                .path
        }
        return preferencesDirectory
            .appendingPathComponent("Flint.plist")
            .path
    }
}
