import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?

    func applicationDidFinishLaunching(_ notification: Notification) {
        coordinator = AppCoordinator()
        coordinator?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}

@MainActor
final class AppCoordinator: NSObject, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let overlay = OverlayWindow()
    private let recorder = AudioRecorder()
    private let transcriptionEngine = TranscriptionEngine()
    private let dictionaryEngine = DictionaryEngine()
    private let learningStore = LearningStore()
    private let learningMetrics = LearningMetrics()
    private let cleanupEngine = CleanupEngine()
    private let textInsertionEngine = TextInsertionEngine()
    private let dictationFeedback = DictationFeedback()
    private let permissionManager = PermissionManager()
    private let modelManager = ModelManager()
    private let shortcutManager = ShortcutManager()
    private let appSettingsStore = AppSettingsStore()
    private let updateManager = UpdateManager()
    private let licenseAuthorization = LicenseAuthorizationController()
    private let historyStore = try? HistoryStore()
    private let appModeRuleStore = AppModeRuleStore()
    private let appModeResolver = AppModeResolver()
    private let activeAppDetector = ActiveAppDetector()

    private var onboardingWindow: OnboardingWindowController?
    private var memorySnapshot: MemorySnapshot = .empty
    private var isRecording = false
    private var didCancelCurrentRecording = false
    private var recordingStartedAt: Date?
    private var recordingStartActiveApp: ActiveAppInfo?
    private var recordingCleanupMode: CleanupMode?
    private var audioMeterTimer: Timer?
    private var focusedStartInsertionTarget: TextInsertionTarget?
    private var preparingModelTier: ModelTier?
    private var modelPreparationError: String?
    private var processingTimeoutTask: Task<Void, Never>?
    private var activeProcessingID: UUID?
    private var cleanupMode: CleanupMode = .clean {
        didSet {
            appSettingsStore.saveCleanupMode(cleanupMode)
            updateCleanupModeUI()
            settingsWindow?.refresh()
        }
    }
    private var shortcutSettings: ShortcutSettings = .default {
        didSet {
            appSettingsStore.saveShortcutSettings(shortcutSettings)
            shortcutManager.update(settings: shortcutSettings)
            updateShortcutSettingsUI()
            settingsWindow?.refresh()
        }
    }
    private var insertionTargetBehavior: InsertionTargetBehavior = .recordingStart {
        didSet {
            appSettingsStore.saveInsertionTargetBehavior(insertionTargetBehavior)
            updateInsertionTargetBehaviorUI()
            settingsWindow?.refresh()
        }
    }
    private var appAwareModesEnabled = false {
        didSet {
            appSettingsStore.saveAppAwareModesEnabled(appAwareModesEnabled)
            updateAppAwareModesUI()
            settingsWindow?.refresh()
        }
    }
    private weak var cleanupModeMenuItem: NSMenuItem?
    private var cleanupModeSelectionMenuItems: [NSMenuItem] = []
    private weak var shortcutMenuItem: NSMenuItem?
    private var shortcutSelectionMenuItems: [NSMenuItem] = []
    private weak var inputBehaviorMenuItem: NSMenuItem?
    private var inputBehaviorSelectionMenuItems: [NSMenuItem] = []
    private weak var insertionTargetBehaviorMenuItem: NSMenuItem?
    private var insertionTargetBehaviorSelectionMenuItems: [NSMenuItem] = []
    private weak var modelMenuItem: NSMenuItem?
    private var modelSelectionMenuItems: [NSMenuItem] = []
    private weak var downloadModelMenuItem: NSMenuItem?
    private weak var deleteModelMenuItem: NSMenuItem?
    private weak var permissionMenuItem: NSMenuItem?
    private weak var appAwareModesMenuItem: NSMenuItem?
    private weak var fixThisDictationMenuItem: NSMenuItem?
    private var privacyWindow: PrivacyWindowController?
    private var licenseWindow: LicenseWindowController?
    private var appModeSettingsWindow: AppModeSettingsWindowController?
    private var settingsWindow: SettingsWindowController?
    private var fixThisDictationWindow: FixThisDictationWindowController?
    private var recentDictationBuffer = RecentDictationBuffer()

    func start() {
        let settings = appSettingsStore.load()
        cleanupMode = settings.cleanupMode
        shortcutSettings = settings.shortcutSettings
        insertionTargetBehavior = settings.insertionTargetBehavior
        appAwareModesEnabled = settings.appAwareModesEnabled
        configureMenu()
        updateCleanupModeUI()
        updateShortcutSettingsUI()
        updateInsertionTargetBehaviorUI()
        updateAppAwareModesUI()
        updateModelMenuUI()
        overlay.show(state: .ready)
        licenseAuthorization.start()
        Task { [weak self] in
            await self?.initializeLearning()
        }

        shortcutManager.onStart = { [weak self] in
            Task { @MainActor in
                await self?.startDictation()
            }
        }
        shortcutManager.onFinish = { [weak self] in
            Task { @MainActor in
                await self?.finishDictation()
            }
        }
        shortcutManager.onCancel = { [weak self] in
            Task { @MainActor in
                await self?.cancelDictation()
            }
        }
        ensureShortcutMonitoringStarted()
        updatePermissionMenuItem()
        prepareSelectedModelIfInstalled()
        if !settings.hasCompletedOnboarding {
            showOnboarding()
        }
    }

    func stop() {
        stopAudioMetering()
        processingTimeoutTask?.cancel()
        processingTimeoutTask = nil
        activeProcessingID = nil
        shortcutManager.stop()
        licenseAuthorization.stop()
    }

    private func configureMenu() {
        statusItem.button?.title = "F"
        statusItem.button?.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        statusItem.button?.toolTip = "Flint"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start/Pause Dictation", action: #selector(toggleDictation), keyEquivalent: ""))
        let fixItem = NSMenuItem(
            title: "Fix This Dictation…",
            action: #selector(showFixThisDictation),
            keyEquivalent: ""
        )
        fixItem.isEnabled = false
        menu.addItem(fixItem)
        fixThisDictationMenuItem = fixItem
        let modeItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let modeSubmenu = NSMenu()
        cleanupModeSelectionMenuItems = CleanupMode.allCases.map { mode in
            let item = NSMenuItem(title: mode.displayName, action: #selector(selectCleanupMode(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            modeSubmenu.addItem(item)
            return item
        }
        modeItem.submenu = modeSubmenu
        menu.addItem(modeItem)
        cleanupModeMenuItem = modeItem
        let appAwareModesItem = NSMenuItem(title: "", action: #selector(toggleAppAwareModes), keyEquivalent: "")
        appAwareModesItem.target = self
        menu.addItem(appAwareModesItem)
        appAwareModesMenuItem = appAwareModesItem
        menu.addItem(NSMenuItem(title: "Configure App Modes...", action: #selector(showAppModeSettings), keyEquivalent: ""))
        let shortcutItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let shortcutSubmenu = NSMenu()
        shortcutSelectionMenuItems = ShortcutOption.allCases.map { option in
            let item = NSMenuItem(title: option.displayName, action: #selector(selectShortcut(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.rawValue
            shortcutSubmenu.addItem(item)
            return item
        }
        shortcutItem.submenu = shortcutSubmenu
        menu.addItem(shortcutItem)
        shortcutMenuItem = shortcutItem
        let behaviorItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let behaviorSubmenu = NSMenu()
        inputBehaviorSelectionMenuItems = ShortcutInputBehavior.allCases.map { behavior in
            let item = NSMenuItem(title: behavior.displayName, action: #selector(selectInputBehavior(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = behavior.rawValue
            behaviorSubmenu.addItem(item)
            return item
        }
        behaviorItem.submenu = behaviorSubmenu
        menu.addItem(behaviorItem)
        inputBehaviorMenuItem = behaviorItem
        let insertionTargetItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let insertionTargetSubmenu = NSMenu()
        insertionTargetBehaviorSelectionMenuItems = InsertionTargetBehavior.allCases.map { behavior in
            let item = NSMenuItem(title: behavior.displayName, action: #selector(selectInsertionTargetBehavior(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = behavior.rawValue
            insertionTargetSubmenu.addItem(item)
            return item
        }
        insertionTargetItem.submenu = insertionTargetSubmenu
        menu.addItem(insertionTargetItem)
        insertionTargetBehaviorMenuItem = insertionTargetItem
        let modelItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        let modelSubmenu = NSMenu()
        modelSelectionMenuItems = ModelTier.allCases.map { tier in
            let metadata = modelManager.metadata(for: tier)
            let item = NSMenuItem(title: modelSelectionTitle(for: metadata), action: #selector(selectModelTier(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = tier.rawValue
            modelSubmenu.addItem(item)
            return item
        }
        modelSubmenu.addItem(.separator())
        let downloadItem = NSMenuItem(title: "", action: #selector(downloadSelectedModel), keyEquivalent: "")
        downloadItem.target = self
        modelSubmenu.addItem(downloadItem)
        downloadModelMenuItem = downloadItem
        let deleteItem = NSMenuItem(title: "", action: #selector(deleteSelectedModel), keyEquivalent: "")
        deleteItem.target = self
        modelSubmenu.addItem(deleteItem)
        deleteModelMenuItem = deleteItem
        modelItem.submenu = modelSubmenu
        menu.addItem(modelItem)
        modelMenuItem = modelItem
        menu.addItem(.separator())
        let permissionItem = NSMenuItem(title: "", action: #selector(showPermissions), keyEquivalent: "")
        menu.addItem(permissionItem)
        permissionMenuItem = permissionItem
        menu.addItem(NSMenuItem(title: "Onboarding", action: #selector(showOnboarding), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Privacy", action: #selector(showPrivacy), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "License", action: #selector(showLicense), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
        menu.delegate = self
        statusItem.menu = menu
        updatePermissionMenuItem()
        updateModelMenuUI()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updatePermissionMenuItem()
        fixThisDictationMenuItem?.isEnabled = !recentDictationBuffer.isEmpty
    }

    private func updateCleanupModeUI() {
        cleanupModeMenuItem?.title = "Current Mode: \(cleanupMode.displayName)"
        for item in cleanupModeSelectionMenuItems {
            item.state = item.representedObject as? String == cleanupMode.rawValue ? .on : .off
        }
    }

    private func updateShortcutSettingsUI() {
        shortcutMenuItem?.title = "Shortcut: \(shortcutSettings.option.displayName)"
        for item in shortcutSelectionMenuItems {
            item.state = item.representedObject as? String == shortcutSettings.option.rawValue ? .on : .off
        }

        inputBehaviorMenuItem?.title = "Input Behavior: \(shortcutSettings.behavior.displayName)"
        for item in inputBehaviorSelectionMenuItems {
            item.state = item.representedObject as? String == shortcutSettings.behavior.rawValue ? .on : .off
        }

    }

    private func updateInsertionTargetBehaviorUI() {
        insertionTargetBehaviorMenuItem?.title = "Insertion Target: \(insertionTargetBehavior.displayName)"
        for item in insertionTargetBehaviorSelectionMenuItems {
            item.state = item.representedObject as? String == insertionTargetBehavior.rawValue ? .on : .off
        }
    }

    private func updateAppAwareModesUI() {
        appAwareModesMenuItem?.title = "App-Aware Modes: \(appAwareModesEnabled ? "On" : "Off")"
        appAwareModesMenuItem?.state = appAwareModesEnabled ? .on : .off
    }

    private func updateModelMenuUI() {
        let selectedTier = modelManager.selectedTier()
        let metadata = modelManager.metadata(for: selectedTier)
        modelMenuItem?.title = modelMenuTitle(for: selectedTier)
        for item in modelSelectionMenuItems {
            guard let rawValue = item.representedObject as? String,
                  let tier = ModelTier(rawValue: rawValue) else {
                continue
            }
            item.title = modelSelectionTitle(for: modelManager.metadata(for: tier))
            item.state = tier == selectedTier ? .on : .off
        }
        downloadModelMenuItem?.title = metadata.isInstalled
            ? "\(selectedTier.displayName) Installed"
            : "Download \(selectedTier.displayName)"
        downloadModelMenuItem?.isEnabled = !metadata.isInstalled
        deleteModelMenuItem?.title = "Delete \(selectedTier.displayName)"
        deleteModelMenuItem?.isEnabled = metadata.isInstalled
        settingsWindow?.refresh()
    }

    private func modelSelectionTitle(for metadata: ModelMetadata) -> String {
        let installedSuffix = metadata.isInstalled ? "installed" : "not installed"
        return "\(metadata.displayName) - \(metadata.sizeLabel) - \(metadata.hardwareLabel) - \(installedSuffix)"
    }

    private func modelMenuTitle(for tier: ModelTier) -> String {
        if preparingModelTier == tier {
            return "Model: \(tier.displayName) (Preparing...)"
        }
        if modelPreparationError != nil {
            return "Model: \(tier.displayName) (Unavailable)"
        }
        return "Model: \(tier.displayName)"
    }

    private func updatePermissionMenuItem() {
        let snapshot = permissionManager.snapshot()
        if snapshot.missingCount == 0 {
            permissionMenuItem?.title = "Permissions: Ready"
        } else {
            permissionMenuItem?.title = "Permissions: \(snapshot.missingCount) Missing"
        }
    }

    @objc private func toggleDictation() {
        if isRecording {
            Task { await finishDictation() }
        } else {
            Task { await startDictation() }
        }
    }

    @objc private func selectCleanupMode(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selectedMode = CleanupMode(rawValue: rawValue) else {
            return
        }
        cleanupMode = selectedMode
    }

    @objc private func toggleAppAwareModes() {
        appAwareModesEnabled.toggle()
    }

    @objc private func selectShortcut(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selectedShortcut = ShortcutOption(rawValue: rawValue) else {
            return
        }
        shortcutSettings.option = selectedShortcut
    }

    @objc private func selectInputBehavior(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selectedBehavior = ShortcutInputBehavior(rawValue: rawValue) else {
            return
        }
        shortcutSettings.behavior = selectedBehavior
    }

    @objc private func selectInsertionTargetBehavior(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selectedBehavior = InsertionTargetBehavior(rawValue: rawValue) else {
            return
        }
        insertionTargetBehavior = selectedBehavior
    }

    @objc private func selectModelTier(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
              let selectedTier = ModelTier(rawValue: rawValue) else {
            return
        }
        appSettingsStore.saveSelectedModelTier(selectedTier)
        prepareSelectedModelIfInstalled()
        updateModelMenuUI()
    }

    @objc private func downloadSelectedModel() {
        downloadModelMenuItem?.isEnabled = false
        Task { @MainActor in
            do {
                _ = try await modelManager.downloadSelectedModel()
                try await transcriptionEngine.prepareSelectedModel()
                updateModelMenuUI()
            } catch {
                updateModelMenuUI()
                showError(title: "Model Download Failed", message: error.localizedDescription)
            }
        }
    }

    @objc private func deleteSelectedModel() {
        do {
            try modelManager.deleteSelectedModel()
            updateModelMenuUI()
        } catch {
            showError(title: "Model Delete Failed", message: error.localizedDescription)
        }
    }

    @objc private func showSettings() {
        if let settingsWindow {
            settingsWindow.show()
            return
        }

        let controller = SettingsWindowController(
            settingsStore: appSettingsStore,
            modelManager: modelManager,
            dictionaryEngine: dictionaryEngine,
            learningStore: learningStore,
            learningMetrics: learningMetrics,
            onSettingsChanged: { [weak self] settings in
                self?.applySettingsFromWindow(settings)
            },
            onModelMetadataChanged: { [weak self] in
                self?.updateModelMenuUI()
            },
            modelPreparationAction: { [modelManager, transcriptionEngine] tier in
                do {
                    try await transcriptionEngine.prepareSelectedModel()
                } catch {
                    try? modelManager.deleteModel(for: tier)
                    throw error
                }
            },
            onShowAppModes: { [weak self] in
                self?.showAppModeSettings()
            },
            onShowPrivacy: { [weak self] in
                self?.showPrivacy()
            },
            onLearningChanged: { [weak self] snapshot in
                self?.memorySnapshot = snapshot
            },
            vocabularyApplicationsProvider: { [weak self] in
                self?.vocabularyApplicationOptions() ?? SettingsModel.runningApplications()
            }
        )
        settingsWindow = controller
        controller.show()
    }

    @objc private func showAppModeSettings() {
        if let appModeSettingsWindow {
            appModeSettingsWindow.show()
            return
        }

        let controller = AppModeSettingsWindowController(
            settingsStore: appSettingsStore,
            ruleStore: appModeRuleStore,
            onSettingsChanged: { [weak self] settings in
                self?.appAwareModesEnabled = settings.appAwareModesEnabled
            }
        )
        appModeSettingsWindow = controller
        controller.show()
    }

    @objc private func showPermissions() {
        let snapshot = permissionManager.snapshot()
        updatePermissionMenuItem()

        let alert = NSAlert()
        alert.messageText = snapshot.missingCount == 0 ? "Permissions Ready" : "Permissions Needed"
        alert.informativeText = snapshot.statuses.map { status in
            "\(status.statusLine)\n\(status.explanation)"
        }.joined(separator: "\n\n")
        alert.addButton(withTitle: "Open Privacy Settings")
        alert.addButton(withTitle: "Prompt Again")
        alert.addButton(withTitle: "OK")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            openPrivacySettings()
        case .alertSecondButtonReturn:
            Task { @MainActor in
                await permissionManager.requestMissingPermissions()
                updatePermissionMenuItem()
                ensureShortcutMonitoringStarted()
            }
        default:
            break
        }
    }

    @objc private func showPrivacy() {
        if let privacyWindow {
            privacyWindow.show()
            return
        }

        let controller = PrivacyWindowController(
            privacyManager: PrivacyManager(
                settingsStore: appSettingsStore,
                dictionaryEngine: dictionaryEngine,
                learningStore: learningStore,
                learningMetrics: learningMetrics,
                modelManager: modelManager,
                historyStore: historyStore,
                permissionSnapshotProvider: { [permissionManager] in
                    permissionManager.snapshot()
                }
            ),
            onDeleteAllLocalData: { [weak self] in
                self?.applyPrivacyDeletionDefaults()
            },
            onLearningChanged: { [weak self] snapshot in
                self?.memorySnapshot = snapshot
            }
        )
        privacyWindow = controller
        controller.show()
    }

    @objc private func showFixThisDictation() {
        guard !recentDictationBuffer.isEmpty else { return }
        Task { [learningMetrics] in
            await learningMetrics.increment(.fixPanelOpens)
        }
        let entries = recentDictationBuffer.newestFirst
        if let fixThisDictationWindow {
            fixThisDictationWindow.update(entries: entries)
            fixThisDictationWindow.show()
            return
        }

        let controller = FixThisDictationWindowController(
            entries: entries,
            learningStore: learningStore,
            onLearningChanged: { [weak self] snapshot in
                self?.memorySnapshot = snapshot
            },
            onSaved: { [learningMetrics] acceptedMapping in
                Task {
                    await learningMetrics.increment(.fixSaves)
                    if acceptedMapping {
                        await learningMetrics.increment(.explicitMappingsAccepted)
                    }
                }
            },
            onCancel: { [learningMetrics] in
                Task { await learningMetrics.increment(.fixCancellations) }
            },
            onProposalShown: { [learningMetrics] in
                Task { await learningMetrics.increment(.eligibleMappingsShown) }
            },
            onDismiss: { [weak self] in
                self?.fixThisDictationWindow = nil
            }
        )
        fixThisDictationWindow = controller
        controller.show()
    }

    @objc private func showOnboarding() {
        if let onboardingWindow {
            onboardingWindow.show()
            return
        }

        let controller = OnboardingWindowController(
            settingsStore: appSettingsStore,
            permissionManager: permissionManager,
            modelManager: modelManager,
            modelPreparationAction: { [modelManager, transcriptionEngine] tier in
                do {
                    try await transcriptionEngine.prepareSelectedModel()
                } catch {
                    try? modelManager.deleteModel(for: tier)
                    throw error
                }
            },
            onTestDictation: { [weak self] in
                self?.toggleDictation()
            },
            onSettingsChanged: { [weak self] settings in
                self?.applyOnboardingSettings(settings)
            },
            onPermissionsChanged: { [weak self] in
                self?.updatePermissionMenuItem()
                self?.ensureShortcutMonitoringStarted()
            },
            onComplete: { [weak self] in
                self?.completeOnboarding()
            }
        )
        onboardingWindow = controller
        controller.show()
    }

    @objc private func checkForUpdates() {
        let alert = NSAlert()
        switch updateManager.readiness() {
        case .ready:
            alert.messageText = "Update Configuration Detected"
            alert.informativeText = "This build contains the bundle metadata required by a Sparkle updater. Flint does not include update checking until the production updater is integrated into the packaged release."
        case .notConfigured(let prerequisites):
            alert.messageText = "Updates Not Configured"
            alert.informativeText = """
            Updates cannot be checked in this build because required production update configuration is missing:

            \(prerequisites.map { "- \($0)" }.joined(separator: "\n"))
            """
        }
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func showLicense() {
        if let licenseWindow {
            licenseWindow.show()
            return
        }

        let controller = LicenseWindowController(
            activationClient: { licenseKey in
                try await ProductionLicenseActivationClient().activate(licenseKey: licenseKey)
            },
            deactivationAction: {
                try await ProductionLicenseActivationClient().deactivateCurrentDevice()
            },
            onActivationChanged: { [weak self] in
                self?.licenseAuthorization.refreshLocalAuthorization()
            }
        )
        licenseWindow = controller
        controller.show()
    }

    private func showNotBuiltYet(_ title: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "This screen is not part of the Phase 1 scaffold yet."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func completeOnboarding() {
        let settings = appSettingsStore.load()
        applyOnboardingSettings(settings)
        updatePermissionMenuItem()
        ensureShortcutMonitoringStarted()
        prepareSelectedModelIfInstalled()
        onboardingWindow?.close()
        onboardingWindow = nil
    }

    private func applyOnboardingSettings(_ settings: AppSettings) {
        shortcutSettings = settings.shortcutSettings
        appAwareModesEnabled = settings.appAwareModesEnabled
        prepareSelectedModelIfInstalled()
        updateModelMenuUI()
    }

    private func applySettingsFromWindow(_ settings: AppSettings) {
        cleanupMode = settings.cleanupMode
        shortcutSettings = settings.shortcutSettings
        insertionTargetBehavior = settings.insertionTargetBehavior
        appAwareModesEnabled = settings.appAwareModesEnabled
        prepareSelectedModelIfInstalled()
        updateModelMenuUI()
    }

    private func applyPrivacyDeletionDefaults() {
        let settings = appSettingsStore.load()
        cleanupMode = settings.cleanupMode
        shortcutSettings = settings.shortcutSettings
        insertionTargetBehavior = settings.insertionTargetBehavior
        appAwareModesEnabled = settings.appAwareModesEnabled
        memorySnapshot = .empty
        updateModelMenuUI()
        updatePermissionMenuItem()
    }

    private func initializeLearning() async {
        do {
            let legacyReplacements = dictionaryEngine.listCustomReplacements()
            _ = try await learningStore.migrateLegacyVocabulary(
                legacyReplacements,
                userDefaults: appSettingsStore.defaults
            )
            memorySnapshot = try await learningStore.memorySnapshot()
            try await learningStore.runRetention()
        } catch {
            memorySnapshot = .empty
            NSLog("Flint learning storage unavailable; continuing with built-in vocabulary: \(error.localizedDescription)")
        }
    }

    private func vocabularyApplicationOptions() -> [VocabularyApplicationOption] {
        var options = SettingsModel.runningApplications()
        var seen = Set(options.map(\.bundleIdentifier))
        for entry in recentDictationBuffer.newestFirst {
            guard let bundleIdentifier = entry.applicationBundleID,
                  !bundleIdentifier.isEmpty,
                  seen.insert(bundleIdentifier).inserted else { continue }
            options.append(VocabularyApplicationOption(
                name: entry.applicationName ?? bundleIdentifier,
                bundleIdentifier: bundleIdentifier
            ))
        }
        return options.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func prepareSelectedModelIfInstalled() {
        let tier = modelManager.selectedTier()
        guard modelManager.metadata(for: tier).isInstalled,
              preparingModelTier != tier else {
            return
        }

        preparingModelTier = tier
        modelPreparationError = nil
        updateModelMenuUI()

        Task { [weak self] in
            guard let self else { return }

            do {
                try await transcriptionEngine.prepareSelectedModel()
                guard modelManager.selectedTier() == tier else { return }
                preparingModelTier = nil
                updateModelMenuUI()
            } catch {
                guard modelManager.selectedTier() == tier else { return }
                try? modelManager.deleteModel(for: tier)
                preparingModelTier = nil
                modelPreparationError = error.localizedDescription
                updateModelMenuUI()
                NSLog("Flint model preparation failed: \(error.localizedDescription)")
            }
        }
    }

    private func selectedModelReadinessMessage() -> String? {
        let tier = modelManager.selectedTier()
        guard modelManager.metadata(for: tier).isInstalled else {
            return "Download the selected model before dictation."
        }
        if preparingModelTier == tier {
            return "Model is preparing. Try dictation again shortly."
        }
        if modelPreparationError != nil {
            return "Selected model could not be prepared. Restart Flint or download it again."
        }
        return nil
    }

    private func beginProcessingTimeout(for processingID: UUID) {
        processingTimeoutTask?.cancel()
        activeProcessingID = processingID
        processingTimeoutTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(90))
            } catch {
                return
            }

            guard let self, activeProcessingID == processingID else { return }
            activeProcessingID = nil
            processingTimeoutTask = nil
            overlay.show(state: .error("Transcription timed out. Try again or choose a smaller model."))
            dictationFeedback.perform(.failed, settings: appSettingsStore.load())
        }
    }

    private func endProcessingTimeout(for processingID: UUID) {
        guard activeProcessingID == processingID else { return }
        processingTimeoutTask?.cancel()
        processingTimeoutTask = nil
        activeProcessingID = nil
    }

    private func ensureShortcutMonitoringStarted() {
        switch shortcutManager.start() {
        case .started:
            break
        case .inputMonitoringMissing:
            guard !shortcutManager.isRunning else { return }
            let inputMonitoring = permissionManager.snapshot().status(for: .inputMonitoring)
            let message = inputMonitoring.isReady
                ? "Shortcut monitoring could not start. Restart Flint, then check Input Monitoring."
                : inputMonitoring.failureMessage
            overlay.show(state: .error(message))
            dictationFeedback.perform(.failed, settings: appSettingsStore.load())
        }
    }

    private func startDictation() async {
        guard !isRecording else { return }

        if let licenseMessage = licenseAuthorization.blockingMessage {
            overlay.show(state: .error(licenseMessage))
            dictationFeedback.perform(.failed, settings: appSettingsStore.load())
            return
        }

        if let modelReadinessMessage = selectedModelReadinessMessage() {
            overlay.show(state: .error(modelReadinessMessage))
            dictationFeedback.perform(.failed, settings: appSettingsStore.load())
            return
        }

        do {
            didCancelCurrentRecording = false
            recordingStartedAt = Date()
            recordingStartActiveApp = activeAppDetector.detect()
            recordingCleanupMode = resolvedCleanupMode(
                for: recordingStartActiveApp,
                settings: appSettingsStore.load()
            )
            focusedStartInsertionTarget = textInsertionEngine.captureFocusedTarget()
            isRecording = true
            overlay.updateAudioLevel(0)
            overlay.show(state: .listening)
            try await recorder.start()
            guard isRecording else {
                let audioURL = try? recorder.stop()
                if let audioURL {
                    try? FileManager.default.removeItem(at: audioURL)
                }
                stopAudioMetering()
                return
            }
            dictationFeedback.perform(.started, settings: appSettingsStore.load())
            startAudioMetering()
        } catch {
            isRecording = false
            recordingStartedAt = nil
            recordingStartActiveApp = nil
            recordingCleanupMode = nil
            focusedStartInsertionTarget = nil
            stopAudioMetering()
            updateCleanupModeUI()
            if let recorderError = error as? AudioRecorder.RecorderError,
               recorderError == .microphonePermissionDenied {
                overlay.show(state: .error(PermissionStatus(kind: .microphone, readiness: .denied).failureMessage))
                updatePermissionMenuItem()
            } else {
                overlay.show(state: .error("Microphone recording failed."))
            }
            dictationFeedback.perform(.failed, settings: appSettingsStore.load())
        }
    }

    private func finishDictation() async {
        guard isRecording else { return }

        isRecording = false
        stopAudioMetering()
        let startedAt = recordingStartedAt
        let activeApp = recordingStartActiveApp
        let effectiveMode = recordingCleanupMode
        defer {
            focusedStartInsertionTarget = nil
            recordingStartedAt = nil
            recordingStartActiveApp = nil
            recordingCleanupMode = nil
            updateCleanupModeUI()
        }

        let audioURL: URL
        do {
            audioURL = try recorder.stop()
            dictationFeedback.perform(.stopped, settings: appSettingsStore.load())
        } catch {
            overlay.show(state: .error("Microphone recording failed."))
            dictationFeedback.perform(.failed, settings: appSettingsStore.load())
            return
        }
        defer { try? FileManager.default.removeItem(at: audioURL) }

        if didCancelCurrentRecording {
            overlay.show(state: .cancelled)
            dictationFeedback.perform(.cancelled, settings: appSettingsStore.load())
            return
        }

        do {
            overlay.show(state: .processingLocally)
            let processingID = UUID()
            beginProcessingTimeout(for: processingID)
            defer { endProcessingTimeout(for: processingID) }

            let appliedSettings = appSettingsStore.load()
            let appliedCleanupMode = effectiveMode ?? resolvedCleanupMode(for: activeApp, settings: appliedSettings)
            let appliedModelName = modelManager.selectedConfigurationDescriptor().modelName
            let transcript = try await transcriptionEngine.transcribe(audioFileURL: audioURL)
            guard activeProcessingID == processingID else { return }
            let dictionaryResult = dictionaryEngine.apply(
                to: transcript,
                snapshot: memorySnapshot,
                activeApp: activeApp,
                language: appliedSettings.language
            )
            let cleanedTranscript = cleanupEngine.clean(
                dictionaryResult.text,
                mode: appliedCleanupMode,
                preferences: CleanupPreferences(
                    removeFillerWords: appliedSettings.removeFillerWords,
                    addTerminalPunctuation: appliedSettings.addTerminalPunctuation
                )
            )

            guard let usableTranscript = DictationOutputPolicy.usableOutput(from: cleanedTranscript) else {
                overlay.show(state: .error(DictationOutputPolicy.emptyOutputMessage))
                dictationFeedback.perform(.failed, settings: appSettingsStore.load())
                return
            }

            overlay.show(state: .inserting)
            let result = await textInsertionEngine.insert(
                usableTranscript,
                preferredTarget: focusedStartInsertionTarget,
                targetBehavior: insertionTargetBehavior
            )
            if result == .inserted {
                overlay.show(state: .ready)
                dictationFeedback.perform(.inserted, settings: appSettingsStore.load())
            } else if !permissionManager.snapshot().status(for: .accessibility).isReady {
                overlay.show(state: .error(PermissionStatus(kind: .accessibility, readiness: .denied).failureMessage))
                updatePermissionMenuItem()
                dictationFeedback.perform(.failed, settings: appSettingsStore.load())
            } else {
                overlay.show(state: .copiedToClipboard)
            }
            recentDictationBuffer.append(RecentDictation(
                rawText: transcript,
                insertedText: usableTranscript,
                applicationName: activeApp?.name,
                applicationBundleID: activeApp?.bundleIdentifier,
                language: appliedSettings.language,
                cleanupMode: appliedCleanupMode,
                deliveryResult: result
            ))
            fixThisDictationMenuItem?.isEnabled = true
            fixThisDictationWindow?.update(entries: recentDictationBuffer.newestFirst)
            Task { [learningMetrics] in
                await learningMetrics.increment(.completedUsableDictations)
                let appliedCount = dictionaryResult.matchedMemoryCounts.values.reduce(0, +)
                if appliedCount > 0 {
                    await learningMetrics.increment(.activeMemoriesApplied, by: appliedCount)
                }
            }
            recordHistoryIfEnabled(
                rawTranscript: transcript,
                finalText: usableTranscript,
                durationMS: durationMS(startedAt: startedAt),
                activeApp: activeApp,
                mode: appliedCleanupMode,
                modelName: appliedModelName,
                settings: appliedSettings
            )
            if !dictionaryResult.matchedMemoryCounts.isEmpty {
                Task { [learningStore] in
                    try? await learningStore.incrementUsageCounts(dictionaryResult.matchedMemoryCounts)
                }
            }
        } catch {
            overlay.show(state: .error(TranscriptionEngine.userFacingMessage(for: error)))
            dictationFeedback.perform(.failed, settings: appSettingsStore.load())
        }
    }

    private func cancelDictation() async {
        guard isRecording else { return }
        didCancelCurrentRecording = true
        isRecording = false
        recordingStartedAt = nil
        recordingStartActiveApp = nil
        recordingCleanupMode = nil
        stopAudioMetering()
        focusedStartInsertionTarget = nil
        if let audioURL = try? recorder.stop() {
            try? FileManager.default.removeItem(at: audioURL)
        }
        updateCleanupModeUI()
        overlay.show(state: .cancelled)
        dictationFeedback.perform(.cancelled, settings: appSettingsStore.load())
    }

    private func startAudioMetering() {
        stopAudioMetering()
        overlay.updateAudioLevel(0)

        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateAudioMeter()
            }
        }
        audioMeterTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAudioMetering() {
        audioMeterTimer?.invalidate()
        audioMeterTimer = nil
        overlay.updateAudioLevel(0)
    }

    private func updateAudioMeter() {
        guard isRecording else {
            stopAudioMetering()
            return
        }

        overlay.updateAudioLevel(recorder.currentLevel)
    }

    private func openPrivacySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func recordHistoryIfEnabled(
        rawTranscript: String,
        finalText: String,
        durationMS: Int,
        activeApp: ActiveAppInfo?,
        mode: CleanupMode,
        modelName: String,
        settings: AppSettings
    ) {
        let historyRecorder = DictationHistoryRecorder(
            settingsProvider: { settings },
            historyStore: historyStore
        )
        do {
            _ = try historyRecorder.record(
                rawTranscript: rawTranscript,
                finalText: finalText,
                durationMS: durationMS,
                activeApp: activeApp,
                mode: mode,
                modelName: modelName,
                language: settings.language
            )
        } catch {
            NSLog("Flint history write failed: \(error.localizedDescription)")
        }
    }

    private func resolvedCleanupMode(for activeApp: ActiveAppInfo?, settings: AppSettings) -> CleanupMode {
        guard settings.appAwareModesEnabled else {
            return settings.cleanupMode
        }

        do {
            let rules = try appModeRuleStore.list(includeDisabled: false)
            return appModeResolver.resolve(
                context: AppModeResolutionContext(
                    appAwareModesEnabled: true,
                    manualMode: settings.cleanupMode,
                    activeAppBundleID: activeApp?.bundleIdentifier
                ),
                rules: rules
            )
        } catch {
            NSLog("Flint app mode rule lookup failed: \(error.localizedDescription)")
            return settings.cleanupMode
        }
    }

    private func durationMS(startedAt: Date?) -> Int {
        guard let startedAt else {
            return 0
        }
        return max(0, Int(Date().timeIntervalSince(startedAt) * 1000))
    }
}
