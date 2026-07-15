import AppKit
import ApplicationServices
import Foundation

enum TextInsertionResult: Equatable, Sendable {
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

enum TextInsertionTargetKind: Equatable, Sendable {
    case standard
    case richWebComposer
}

struct TextInsertionTarget {
    let element: AXUIElement
    let kind: TextInsertionTargetKind
    let processIdentifier: pid_t?

    init(
        element: AXUIElement,
        kind: TextInsertionTargetKind = .standard,
        processIdentifier: pid_t? = nil
    ) {
        self.element = element
        self.kind = kind
        self.processIdentifier = processIdentifier ?? Self.processIdentifier(for: element)
    }

    private static func processIdentifier(for element: AXUIElement) -> pid_t? {
        var processIdentifier = pid_t()
        guard AXUIElementGetPid(element, &processIdentifier) == .success else {
            return nil
        }
        return processIdentifier
    }
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
    func insert(
        _ text: String,
        preferredTarget: TextInsertionTarget? = nil,
        targetBehavior: InsertionTargetBehavior = .recordingStart
    ) async -> TextInsertionResult {
        switch targetBehavior {
        case .recordingStart:
            if let preferredTarget, preferredTarget.kind == .richWebComposer {
                return insertIntoCapturedWebComposer(text, preferredTarget: preferredTarget)
            }

            if let preferredTarget, accessibilityInserter(preferredTarget, text) {
                return .inserted
            }

            // Accessibility can return a distinct object instance for the same browser field.
            // Do not use object identity to decide whether the paste fallback is safe to attempt.
            if let focusedTarget = focusedTargetProvider() {
                if focusedTarget.kind == .richWebComposer {
                    return pasteOnceOrCopy(text)
                }
                if accessibilityInserter(focusedTarget, text) {
                    return .inserted
                }
            }

            return pasteOnceOrCopy(text)

        case .transcriptionFinish:
            return insertAtCurrentTargetOrFallback(text)
        }
    }

    @MainActor
    private func insertAtCurrentTargetOrFallback(_ text: String) -> TextInsertionResult {
        if let focusedTarget = focusedTargetProvider() {
            if focusedTarget.kind == .richWebComposer {
                return pasteOnceOrCopy(text)
            }
            if accessibilityInserter(focusedTarget, text) {
                return .inserted
            }
        }

        return pasteOnceOrCopy(text)
    }

    @MainActor
    private func insertIntoCapturedWebComposer(
        _ text: String,
        preferredTarget: TextInsertionTarget
    ) -> TextInsertionResult {
        // Rich web editors often report stale AXValue contents after accepting an
        // AXSelectedText mutation. Retrying through AX or paste can then insert the
        // same dictation twice. Only paste when the captured editor's process still
        // owns keyboard focus, and make that the sole mutation attempt.
        guard let focusedTarget = focusedTargetProvider(),
              focusedTarget.kind == .richWebComposer,
              focusedTarget.processIdentifier == preferredTarget.processIdentifier else {
            copyToClipboard(text)
            return .copiedToClipboard
        }
        return pasteOnceOrCopy(text)
    }

    @MainActor
    private func pasteOnceOrCopy(_ text: String) -> TextInsertionResult {
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
        return TextInsertionTarget(
            element: focusedElement,
            kind: targetKind(for: focusedElement)
        )
    }

    private static func insert(_ target: TextInsertionTarget, _ text: String) -> Bool {
        guard let valueBeforeInsertion = stringValue(
            of: target.element,
            attribute: kAXValueAttribute as CFString
        ) else {
            return false
        }

        let placeholderValue = stringValue(
            of: target.element,
            attribute: kAXPlaceholderValueAttribute as CFString
        )
        if shouldReplacePlaceholderValue(valueBeforeInsertion, placeholderValue: placeholderValue) {
            return replacePlaceholderValue(
                in: target.element,
                placeholderValue: valueBeforeInsertion,
                with: text
            )
        }

        let selectedTextResult = AXUIElementSetAttributeValue(
            target.element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if selectedTextResult == .success {
            // Some content editors update their accessibility tree asynchronously.
            // AX has accepted the mutation, so a second strategy would risk a
            // duplicate even when AXValue still appears unchanged for a moment.
            return true
        }

        guard let selectedRange = selectedTextRange(of: target.element),
              let replacementValue = replacingSelectedText(
                  in: valueBeforeInsertion,
                  selectedRange: selectedRange,
                  with: text
              ) else {
            return false
        }

        return AXUIElementSetAttributeValue(
            target.element,
            kAXValueAttribute as CFString,
            replacementValue as CFTypeRef
        ) == .success
    }

    static func didAccessibilityValueChange(from before: String, to after: String) -> Bool {
        before != after
    }

    static func shouldReplacePlaceholderValue(_ value: String, placeholderValue: String?) -> Bool {
        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedValue.isEmpty else {
            return false
        }

        if let placeholderValue,
           normalizedValue.caseInsensitiveCompare(
               placeholderValue.trimmingCharacters(in: .whitespacesAndNewlines)
           ) == .orderedSame {
            return true
        }

        return knownComposerPlaceholders.contains(normalizedValue.lowercased())
    }

    static func replacingSelectedText(
        in value: String,
        selectedRange: NSRange,
        with text: String
    ) -> String? {
        let valueLength = (value as NSString).length
        guard selectedRange.location != NSNotFound,
              selectedRange.location >= 0,
              selectedRange.length >= 0,
              selectedRange.location <= valueLength,
              selectedRange.length <= valueLength - selectedRange.location else {
            return nil
        }
        return (value as NSString).replacingCharacters(in: selectedRange, with: text)
    }

    private static func replacePlaceholderValue(
        in element: AXUIElement,
        placeholderValue: String,
        with text: String
    ) -> Bool {
        let fullPlaceholderRange = NSRange(location: 0, length: (placeholderValue as NSString).length)
        if setSelectedRange(fullPlaceholderRange, on: element) {
            let result = AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextAttribute as CFString,
                text as CFTypeRef
            )
            if result == .success {
                return true
            }
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            text as CFTypeRef
        ) == .success
    }

    private static func setSelectedRange(_ range: NSRange, on element: AXUIElement) -> Bool {
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let rangeValue = AXValueCreate(.cfRange, &cfRange) else {
            return false
        }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        ) == .success
    }

    private static func stringValue(of element: AXUIElement, attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else {
            return nil
        }
        return value as? String
    }

    private static func selectedTextRange(of element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success,
        let value,
        CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }

        let rangeValue = value as! AXValue
        guard AXValueGetType(rangeValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else {
            return nil
        }
        return NSRange(location: range.location, length: range.length)
    }

    private static func targetKind(for element: AXUIElement) -> TextInsertionTargetKind {
        let value = stringValue(of: element, attribute: kAXValueAttribute as CFString) ?? ""
        let placeholder = stringValue(of: element, attribute: kAXPlaceholderValueAttribute as CFString)
        var processIdentifier = pid_t()
        let bundleIdentifier: String?
        if AXUIElementGetPid(element, &processIdentifier) == .success {
            bundleIdentifier = NSRunningApplication(processIdentifier: processIdentifier)?.bundleIdentifier
        } else {
            bundleIdentifier = nil
        }
        return targetKind(
            value: value,
            placeholderValue: placeholder,
            isInsideWebArea: isInsideWebArea(element),
            bundleIdentifier: bundleIdentifier
        )
    }

    static func targetKind(
        value: String,
        placeholderValue: String?,
        isInsideWebArea: Bool,
        bundleIdentifier: String?
    ) -> TextInsertionTargetKind {
        if isInsideWebArea || bundleIdentifier?.lowercased() == "com.openai.chat" {
            return .richWebComposer
        }

        if let placeholderValue,
           knownComposerPlaceholders.contains(
               placeholderValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
           ) {
            return .richWebComposer
        }

        if shouldReplacePlaceholderValue(value, placeholderValue: placeholderValue) {
            return .richWebComposer
        }
        return .standard
    }

    private static func isInsideWebArea(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<32 {
            guard let candidate = current else { return false }
            if stringValue(of: candidate, attribute: kAXRoleAttribute as CFString) == "AXWebArea" {
                return true
            }

            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                candidate,
                kAXParentAttribute as CFString,
                &parentValue
            ) == .success,
            let parentValue else {
                return false
            }
            current = (parentValue as! AXUIElement)
        }
        return false
    }

    private static let knownComposerPlaceholders: Set<String> = [
        "ask chatgpt",
        "message chatgpt",
        "message claude",
        "ask anything",
        "write a message...",
        "write a message…"
    ]

    private static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct ClipboardManager {
    func pasteWithPreservedClipboard(_ text: String) -> Bool {
        pasteWithPreservedClipboard(text, pasteboard: .general, restoreDelay: 0.75)
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

        let temporaryChangeCount = pasteboard.changeCount
        let pasteSucceeded = sendPasteShortcut()
        guard pasteSucceeded else {
            restore(savedItems, to: pasteboard)
            return false
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            self.restoreIfUnchanged(
                savedItems,
                to: pasteboard,
                expectedChangeCount: temporaryChangeCount
            )
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

    @discardableResult
    func restoreIfUnchanged(
        _ items: [NSPasteboardItem],
        to pasteboard: NSPasteboard,
        expectedChangeCount: Int
    ) -> Bool {
        guard pasteboard.changeCount == expectedChangeCount else {
            return false
        }

        restore(items, to: pasteboard)
        return true
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
