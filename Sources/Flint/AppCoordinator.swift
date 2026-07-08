import AppKit
import ApplicationServices
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
final class AppCoordinator {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let overlay = OverlayWindow()
    private let recorder = AudioRecorder()
    private let transcriptionEngine = TranscriptionEngine()
    private let dictionaryEngine = DictionaryEngine()
    private let cleanupEngine = CleanupEngine()
    private let textInsertionEngine = TextInsertionEngine()
    private let shortcutManager = ShortcutManager()
    private let defaults = UserDefaults.standard
    private let cleanupModeDefaultsKey = "cleanupMode"

    private var isRecording = false
    private var didCancelCurrentRecording = false
    private var focusedStartInsertionTarget: TextInsertionTarget?
    private var cleanupMode: CleanupMode = .clean {
        didSet {
            defaults.set(cleanupMode.rawValue, forKey: cleanupModeDefaultsKey)
            updateCleanupModeUI()
        }
    }
    private weak var cleanupModeMenuItem: NSMenuItem?

    func start() {
        cleanupMode = CleanupMode(rawValue: defaults.string(forKey: cleanupModeDefaultsKey) ?? "") ?? .clean
        configureMenu()
        updateCleanupModeUI()
        overlay.show(state: .ready)

        shortcutManager.onPushToTalkDown = { [weak self] in
            Task { @MainActor in
                await self?.startDictation()
            }
        }
        shortcutManager.onPushToTalkUp = { [weak self] in
            Task { @MainActor in
                await self?.finishDictation()
            }
        }
        shortcutManager.onCancel = { [weak self] in
            Task { @MainActor in
                await self?.cancelDictation()
            }
        }
        shortcutManager.start()
    }

    func stop() {
        shortcutManager.stop()
    }

    private func configureMenu() {
        statusItem.button?.title = "F"
        statusItem.button?.font = .monospacedSystemFont(ofSize: 14, weight: .semibold)
        statusItem.button?.toolTip = "Flint"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Start/Pause Dictation", action: #selector(toggleDictation), keyEquivalent: ""))
        let modeItem = NSMenuItem(title: "", action: #selector(toggleCleanupMode), keyEquivalent: "")
        menu.addItem(modeItem)
        cleanupModeMenuItem = modeItem
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Privacy", action: #selector(showPrivacy), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Check for Updates", action: #selector(checkForUpdates), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "License", action: #selector(showLicense), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }
        statusItem.menu = menu
    }

    private func updateCleanupModeUI() {
        cleanupModeMenuItem?.title = "Current Mode: \(cleanupMode.displayName)"
        overlay.setModeLabel(cleanupMode.displayName.uppercased())
    }

    @objc private func toggleDictation() {
        if isRecording {
            Task { await finishDictation() }
        } else {
            Task { await startDictation() }
        }
    }

    @objc private func toggleCleanupMode() {
        cleanupMode = cleanupMode == .clean ? .verbatim : .clean
    }

    @objc private func showSettings() {
        showNotBuiltYet("Settings")
    }

    @objc private func showPrivacy() {
        showNotBuiltYet("Privacy")
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
            overlay.show(state: .listening)
            try await recorder.start()
        } catch {
            isRecording = false
            focusedStartInsertionTarget = nil
            overlay.show(state: .error("Microphone recording failed."))
            NSSound.beep()
        }
    }

    private func finishDictation() async {
        guard isRecording else { return }

        isRecording = false
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
            overlay.show(state: result == .inserted ? .ready : .copiedToClipboard)
        } catch {
            overlay.show(state: .error(error.localizedDescription))
            NSSound.beep()
        }
    }

    private func cancelDictation() async {
        guard isRecording else { return }
        didCancelCurrentRecording = true
        isRecording = false
        focusedStartInsertionTarget = nil
        _ = try? recorder.stop()
        overlay.show(state: .cancelled)
    }
}

final class ShortcutManager {
    var onPushToTalkDown: (() -> Void)?
    var onPushToTalkUp: (() -> Void)?
    var onCancel: (() -> Void)?

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isRightOptionDown = false

    func start() {
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<ShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handle(proxy: proxy, type: type, event: event)
        }

        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        )

        guard let eventTap else {
            requestInputMonitoringHint()
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap {
            CFMachPortInvalidate(eventTap)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            handleFlagsChanged(event)
        } else if type == .keyDown, event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            onCancel?()
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFlagsChanged(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keyCode == 61 else { return } // Right Option.

        let isDown = event.flags.contains(.maskAlternate)
        if isDown && !isRightOptionDown {
            isRightOptionDown = true
            onPushToTalkDown?()
        } else if !isDown && isRightOptionDown {
            isRightOptionDown = false
            onPushToTalkUp?()
        }
    }

    private func requestInputMonitoringHint() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
