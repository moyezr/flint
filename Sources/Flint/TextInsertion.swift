import AppKit
import ApplicationServices
import Foundation

enum TextInsertionResult {
    case inserted
    case copiedToClipboard
}

enum InsertionTargetBehavior: String, CaseIterable {
    case recordingStart
    case transcriptionFinish

    var displayName: String {
        switch self {
        case .recordingStart:
            return "Recording Start"
        case .transcriptionFinish:
            return "Transcription Finish"
        }
    }
}

struct InsertionTargetBehaviorStore {
    let defaults: UserDefaults
    let key: String

    init(defaults: UserDefaults = .standard, key: String = "insertionTargetBehavior") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> InsertionTargetBehavior {
        InsertionTargetBehavior(rawValue: defaults.string(forKey: key) ?? "") ?? .recordingStart
    }

    func save(_ behavior: InsertionTargetBehavior) {
        defaults.set(behavior.rawValue, forKey: key)
    }
}

struct TextInsertionTarget {
    let element: AXUIElement
}

struct TextInsertionEngine {
    private let focusedTargetProvider: @MainActor () -> TextInsertionTarget?
    private let accessibilityInserter: @MainActor (TextInsertionTarget, String) -> Bool
    private let targetMatcher: @MainActor (TextInsertionTarget, TextInsertionTarget) -> Bool
    private let pasteFallback: @MainActor (String) -> Bool
    private let copyToClipboard: @MainActor (String) -> Void

    init(
        focusedTargetProvider: @escaping @MainActor () -> TextInsertionTarget? = TextInsertionEngine.focusedTarget,
        accessibilityInserter: @escaping @MainActor (TextInsertionTarget, String) -> Bool = TextInsertionEngine.insert,
        targetMatcher: @escaping @MainActor (TextInsertionTarget, TextInsertionTarget) -> Bool = TextInsertionEngine.targetsMatch,
        pasteFallback: @escaping @MainActor (String) -> Bool = { ClipboardManager().pasteWithPreservedClipboard($0) },
        copyToClipboard: @escaping @MainActor (String) -> Void = TextInsertionEngine.copyToClipboard
    ) {
        self.focusedTargetProvider = focusedTargetProvider
        self.accessibilityInserter = accessibilityInserter
        self.targetMatcher = targetMatcher
        self.pasteFallback = pasteFallback
        self.copyToClipboard = copyToClipboard
    }

    @MainActor
    func captureFocusedTarget() -> TextInsertionTarget? {
        focusedTargetProvider()
    }

    @MainActor
    func insert(
        _ text: String,
        preferredTarget: TextInsertionTarget? = nil,
        targetBehavior: InsertionTargetBehavior = .recordingStart
    ) async -> TextInsertionResult {
        switch targetBehavior {
        case .recordingStart:
            if let preferredTarget, accessibilityInserter(preferredTarget, text) {
                return .inserted
            }

            if let preferredTarget,
               let focusedTarget = focusedTargetProvider(),
               targetMatcher(preferredTarget, focusedTarget),
               pasteFallback(text) {
                return .inserted
            }

            copyToClipboard(text)
            return .copiedToClipboard

        case .transcriptionFinish:
            return insertAtCurrentTargetOrFallback(text)
        }
    }

    @MainActor
    private func insertAtCurrentTargetOrFallback(_ text: String) -> TextInsertionResult {
        if let focusedTarget = focusedTargetProvider(),
           accessibilityInserter(focusedTarget, text) {
            return .inserted
        }

        if pasteFallback(text) {
            return .inserted
        }

        copyToClipboard(text)
        return .copiedToClipboard
    }

    private static func focusedTarget() -> TextInsertionTarget? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObject) == .success,
              let focusedObject else {
            return nil
        }

        let focusedElement = focusedObject as! AXUIElement
        return TextInsertionTarget(element: focusedElement)
    }

    private static func insert(_ target: TextInsertionTarget, _ text: String) -> Bool {
        AXUIElementSetAttributeValue(target.element, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
    }

    private static func targetsMatch(_ lhs: TextInsertionTarget, _ rhs: TextInsertionTarget) -> Bool {
        CFEqual(lhs.element, rhs.element)
    }

    private static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct ClipboardManager {
    func pasteWithPreservedClipboard(_ text: String) -> Bool {
        pasteWithPreservedClipboard(text, pasteboard: .general, restoreDelay: 0.25)
    }

    func pasteWithPreservedClipboard(
        _ text: String,
        pasteboard: NSPasteboard,
        restoreDelay: TimeInterval
    ) -> Bool {
        let savedItems = snapshotItems(from: pasteboard)

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            restore(savedItems, to: pasteboard)
            return false
        }

        let pasteSucceeded = sendPasteShortcut()
        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            restore(savedItems, to: pasteboard)
        }
        return pasteSucceeded
    }

    func snapshotItems(from pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        pasteboard.pasteboardItems?.compactMap { item -> NSPasteboardItem? in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                } else if let string = item.string(forType: type) {
                    copy.setString(string, forType: type)
                }
            }
            return copy.types.isEmpty ? nil : copy
        } ?? []
    }

    func restore(_ items: [NSPasteboardItem], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if !items.isEmpty {
            pasteboard.writeObjects(items)
        }
    }

    private func sendPasteShortcut() -> Bool {
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return false
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }
}
