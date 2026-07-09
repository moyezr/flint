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
    private let cleanupEngine = CleanupEngine()
    private let textInsertionEngine = TextInsertionEngine()
    private let permissionManager = PermissionManager()
    private let modelManager = ModelManager()
    private let shortcutManager = ShortcutManager()
    private let appSettingsStore = AppSettingsStore()

    private var isRecording = false
    private var didCancelCurrentRecording = false
    private var audioMeterTimer: Timer?
    private var focusedStartInsertionTarget: TextInsertionTarget?
    private var cleanupMode: CleanupMode = .clean {
        didSet {
            appSettingsStore.saveCleanupMode(cleanupMode)
            updateCleanupModeUI()
        }
    }
    private var shortcutSettings: ShortcutSettings = .default {
        didSet {
            appSettingsStore.saveShortcutSettings(shortcutSettings)
            shortcutManager.update(settings: shortcutSettings)
            updateShortcutSettingsUI()
        }
    }
    private var insertionTargetBehavior: InsertionTargetBehavior = .recordingStart {
        didSet {
            appSettingsStore.saveInsertionTargetBehavior(insertionTargetBehavior)
            updateInsertionTargetBehaviorUI()
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

    func start() {
        let settings = appSettingsStore.load()
        cleanupMode = settings.cleanupMode
        shortcutSettings = settings.shortcutSettings
        insertionTargetBehavior = settings.insertionTargetBehavior
        configureMenu()
        updateCleanupModeUI()
        updateShortcutSettingsUI()
        updateInsertionTargetBehaviorUI()
        updateModelMenuUI()
        overlay.show(state: .ready)

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
        switch shortcutManager.start() {
        case .started:
            break
        case .inputMonitoringMissing:
            overlay.show(state: .error(PermissionStatus(kind: .inputMonitoring, readiness: .denied).failureMessage))
            NSSound.beep()
        }
        updatePermissionMenuItem()
    }

    func stop() {
        stopAudioMetering()
        shortcutManager.stop()
    }

    private func configureMenu() {
        statusItem.button?.title = "F"
        statusItem.button?.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        statusItem.button?.toolTip = "Flint"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start/Pause Dictation", action: #selector(toggleDictation), keyEquivalent: ""))
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
    }

    private func updateCleanupModeUI() {
        cleanupModeMenuItem?.title = "Current Mode: \(cleanupMode.displayName)"
        for item in cleanupModeSelectionMenuItems {
            item.state = item.representedObject as? String == cleanupMode.rawValue ? .on : .off
        }
        overlay.setModeLabel(cleanupMode.displayName.uppercased())
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

        overlay.setShortcutSettings(shortcutSettings)
    }

    private func updateInsertionTargetBehaviorUI() {
        insertionTargetBehaviorMenuItem?.title = "Insertion Target: \(insertionTargetBehavior.displayName)"
        for item in insertionTargetBehaviorSelectionMenuItems {
            item.state = item.representedObject as? String == insertionTargetBehavior.rawValue ? .on : .off
        }
    }

    private func updateModelMenuUI() {
        let selectedTier = modelManager.selectedTier()
        let metadata = modelManager.metadata(for: selectedTier)
        modelMenuItem?.title = "Model: \(selectedTier.displayName)"
        for item in modelSelectionMenuItems {
            guard let rawValue = item.representedObject as? String,
                  let tier = ModelTier(rawValue: rawValue) else {
                continue
            }
            item.title = modelSelectionTitle(for: modelManager.metadata(for: tier))
            item.state = tier == selectedTier ? .on : .off
        }
        downloadModelMenuItem?.title = metadata.isInstalled
            ? "Download \(selectedTier.displayName) Again"
            : "Download \(selectedTier.displayName)"
        deleteModelMenuItem?.title = "Delete \(selectedTier.displayName)"
        deleteModelMenuItem?.isEnabled = metadata.isInstalled
    }

    private func modelSelectionTitle(for metadata: ModelMetadata) -> String {
        let installedSuffix = metadata.isInstalled ? "installed" : "not installed"
        return "\(metadata.displayName) - \(metadata.sizeLabel) - \(metadata.hardwareLabel) - \(installedSuffix)"
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
        updateModelMenuUI()
    }

    @objc private func downloadSelectedModel() {
        downloadModelMenuItem?.isEnabled = false
        Task { @MainActor in
            do {
                _ = try await modelManager.downloadSelectedModel()
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
        showNotBuiltYet("Settings")
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
            permissionManager.requestAccessibilityPrompt()
            permissionManager.requestInputMonitoringPrompt()
        default:
            break
        }
    }

    @objc private func showPrivacy() {
        showPermissions()
    }

    @objc private func checkForUpdates() {
        showNotBuiltYet("Updates")
    }

    @objc private func showLicense() {
        showNotBuiltYet("License")
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

    private func startDictation() async {
        guard !isRecording else { return }

        do {
            didCancelCurrentRecording = false
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
            startAudioMetering()
        } catch {
            isRecording = false
            focusedStartInsertionTarget = nil
            stopAudioMetering()
            if let recorderError = error as? AudioRecorder.RecorderError,
               recorderError == .microphonePermissionDenied {
                overlay.show(state: .error(PermissionStatus(kind: .microphone, readiness: .denied).failureMessage))
                updatePermissionMenuItem()
            } else {
                overlay.show(state: .error("Microphone recording failed."))
            }
            NSSound.beep()
        }
    }

    private func finishDictation() async {
        guard isRecording else { return }

        isRecording = false
        stopAudioMetering()
        defer { focusedStartInsertionTarget = nil }

        let audioURL: URL
        do {
            audioURL = try recorder.stop()
        } catch {
            overlay.show(state: .error("Microphone recording failed."))
            NSSound.beep()
            return
        }
        defer { try? FileManager.default.removeItem(at: audioURL) }

        if didCancelCurrentRecording {
            overlay.show(state: .cancelled)
            return
        }

        do {
            overlay.show(state: .processingLocally)
            let transcript = try await transcriptionEngine.transcribe(audioFileURL: audioURL)
            let dictionaryTranscript = dictionaryEngine.apply(to: transcript)
            let cleanedTranscript = cleanupEngine.clean(dictionaryTranscript, mode: cleanupMode)

            guard let usableTranscript = DictationOutputPolicy.usableOutput(from: cleanedTranscript) else {
                overlay.show(state: .error(DictationOutputPolicy.emptyOutputMessage))
                NSSound.beep()
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
            } else if !permissionManager.snapshot().status(for: .accessibility).isReady {
                overlay.show(state: .error(PermissionStatus(kind: .accessibility, readiness: .denied).failureMessage))
                updatePermissionMenuItem()
            } else {
                overlay.show(state: .copiedToClipboard)
            }
        } catch {
            overlay.show(state: .error(TranscriptionEngine.userFacingMessage(for: error)))
            NSSound.beep()
        }
    }

    private func cancelDictation() async {
        guard isRecording else { return }
        didCancelCurrentRecording = true
        isRecording = false
        stopAudioMetering()
        focusedStartInsertionTarget = nil
        if let audioURL = try? recorder.stop() {
            try? FileManager.default.removeItem(at: audioURL)
        }
        overlay.show(state: .cancelled)
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
}
