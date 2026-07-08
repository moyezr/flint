import AppKit
import ApplicationServices
import Foundation

enum TextInsertionResult {
    case inserted
    case copiedToClipboard
}

struct TextInsertionTarget {
    let element: AXUIElement
}

struct TextInsertionEngine {
    private let focusedTargetProvider: @MainActor () -> TextInsertionTarget?
    private let accessibilityInserter: @MainActor (TextInsertionTarget, String) -> Bool
    private let pasteFallback: @MainActor (String) -> Bool
    private let copyToClipboard: @MainActor (String) -> Void

    init(
        focusedTargetProvider: @escaping @MainActor () -> TextInsertionTarget? = TextInsertionEngine.focusedTarget,
        accessibilityInserter: @escaping @MainActor (TextInsertionTarget, String) -> Bool = TextInsertionEngine.insert,
        pasteFallback: @escaping @MainActor (String) -> Bool = { ClipboardManager().pasteWithPreservedClipboard($0) },
        copyToClipboard: @escaping @MainActor (String) -> Void = TextInsertionEngine.copyToClipboard
    ) {
        self.focusedTargetProvider = focusedTargetProvider
        self.accessibilityInserter = accessibilityInserter
        self.pasteFallback = pasteFallback
        self.copyToClipboard = copyToClipboard
    }

    @MainActor
    func captureFocusedTarget() -> TextInsertionTarget? {
        focusedTargetProvider()
    }

    @MainActor
    func insert(_ text: String, preferredTarget: TextInsertionTarget? = nil) async -> TextInsertionResult {
        if let preferredTarget, accessibilityInserter(preferredTarget, text) {
            return .inserted
        }

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
