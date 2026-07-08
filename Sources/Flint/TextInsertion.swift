import AppKit
import ApplicationServices
import Foundation

enum TextInsertionResult {
    case inserted
    case copiedToClipboard
}

struct TextInsertionEngine {
    private let clipboardManager = ClipboardManager()

    @MainActor
    func insert(_ text: String) async -> TextInsertionResult {
        if tryAccessibilityInsertion(text) {
            return .inserted
        }

        if clipboardManager.pasteWithPreservedClipboard(text) {
            return .inserted
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return .copiedToClipboard
    }

    private func tryAccessibilityInsertion(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedObject: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedObject) == .success,
              let focusedObject else {
            return false
        }

        let focusedElement = focusedObject as! AXUIElement
        return AXUIElementSetAttributeValue(focusedElement, kAXSelectedTextAttribute as CFString, text as CFTypeRef) == .success
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
