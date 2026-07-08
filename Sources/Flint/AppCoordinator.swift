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
    private let shortcutManager = ShortcutManager()
    private let cleanupModeSelectionStore = CleanupModeSelectionStore()
    private let shortcutSettingsStore = ShortcutSettingsStore()

    private var isRecording = false
    private var didCancelCurrentRecording = false
    private var audioMeterTimer: Timer?
    private var focusedStartInsertionTarget: TextInsertionTarget?
    private var cleanupMode: CleanupMode = .clean {
        didSet {
            cleanupModeSelectionStore.save(cleanupMode)
            updateCleanupModeUI()
        }
    }
    private var shortcutSettings: ShortcutSettings = .default {
        didSet {
            shortcutSettingsStore.save(shortcutSettings)
            shortcutManager.update(settings: shortcutSettings)
            updateShortcutSettingsUI()
        }
    }
    private weak var cleanupModeMenuItem: NSMenuItem?
    private var cleanupModeSelectionMenuItems: [NSMenuItem] = []
    private weak var shortcutMenuItem: NSMenuItem?
    private var shortcutSelectionMenuItems: [NSMenuItem] = []
    private weak var inputBehaviorMenuItem: NSMenuItem?
    private var inputBehaviorSelectionMenuItems: [NSMenuItem] = []
    private weak var permissionMenuItem: NSMenuItem?

    func start() {
        cleanupMode = cleanupModeSelectionStore.load()
        shortcutSettings = shortcutSettingsStore.load()
        configureMenu()
        updateCleanupModeUI()
        updateShortcutSettingsUI()
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

        do {
            let audioURL = try recorder.stop()
            if didCancelCurrentRecording {
                try? FileManager.default.removeItem(at: audioURL)
                overlay.show(state: .cancelled)
                return
            }

            overlay.show(state: .processingLocally)
            let transcript = try await transcriptionEngine.transcribe(audioFileURL: audioURL)
            try? FileManager.default.removeItem(at: audioURL)
            let dictionaryTranscript = dictionaryEngine.apply(to: transcript)
            let cleanedTranscript = cleanupEngine.clean(dictionaryTranscript, mode: cleanupMode)

            guard !cleanedTranscript.isEmpty else {
                overlay.show(state: .copiedToClipboard)
                return
            }

            overlay.show(state: .inserting)
            let result = await textInsertionEngine.insert(cleanedTranscript, preferredTarget: focusedStartInsertionTarget)
            if result == .inserted {
                overlay.show(state: .ready)
            } else if !permissionManager.snapshot().status(for: .accessibility).isReady {
                overlay.show(state: .error(PermissionStatus(kind: .accessibility, readiness: .denied).failureMessage))
                updatePermissionMenuItem()
            } else {
                overlay.show(state: .copiedToClipboard)
            }
        } catch {
            overlay.show(state: .error(error.localizedDescription))
            NSSound.beep()
        }
    }

    private func cancelDictation() async {
        guard isRecording else { return }
        didCancelCurrentRecording = true
        isRecording = false
        stopAudioMetering()
        focusedStartInsertionTarget = nil
        _ = try? recorder.stop()
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
