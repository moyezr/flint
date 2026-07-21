import ApplicationServices
import Foundation

enum ShortcutOption: String, CaseIterable {
    case rightOption
    case fn
    case controlSpace
    case commandShiftSpace

    var displayName: String {
        switch self {
        case .rightOption:
            return "Right Option"
        case .fn:
            return "Fn"
        case .controlSpace:
            return "Control+Space"
        case .commandShiftSpace:
            return "Cmd+Shift+Space"
        }
    }

}

enum ShortcutInputBehavior: String, CaseIterable {
    case pushToTalk
    case toggle

    var displayName: String {
        switch self {
        case .pushToTalk:
            return "Push-to-Talk"
        case .toggle:
            return "Toggle"
        }
    }
}

struct ShortcutSettings: Equatable {
    var option: ShortcutOption
    var behavior: ShortcutInputBehavior

    static let `default` = ShortcutSettings(option: .rightOption, behavior: .pushToTalk)

    var readyHint: String {
        switch behavior {
        case .pushToTalk:
            return "Hold \(option.displayName) to dictate"
        case .toggle:
            return "Press \(option.displayName) to dictate"
        }
    }

    var listeningHint: String {
        switch behavior {
        case .pushToTalk:
            return "Release to insert · Esc cancel"
        case .toggle:
            return "Press again to insert · Esc cancel"
        }
    }
}

struct ShortcutSettingsStore {
    let defaults: UserDefaults
    let shortcutKey: String
    let behaviorKey: String

    init(
        defaults: UserDefaults = .standard,
        shortcutKey: String = "shortcutOption",
        behaviorKey: String = "shortcutInputBehavior"
    ) {
        self.defaults = defaults
        self.shortcutKey = shortcutKey
        self.behaviorKey = behaviorKey
    }

    func load() -> ShortcutSettings {
        ShortcutSettings(
            option: ShortcutOption(rawValue: defaults.string(forKey: shortcutKey) ?? "") ?? ShortcutSettings.default.option,
            behavior: ShortcutInputBehavior(rawValue: defaults.string(forKey: behaviorKey) ?? "") ?? ShortcutSettings.default.behavior
        )
    }

    func save(_ settings: ShortcutSettings) {
        defaults.set(settings.option.rawValue, forKey: shortcutKey)
        defaults.set(settings.behavior.rawValue, forKey: behaviorKey)
    }
}

struct ShortcutModifiers: OptionSet, Equatable {
    let rawValue: Int

    static let control = ShortcutModifiers(rawValue: 1 << 0)
    static let command = ShortcutModifiers(rawValue: 1 << 1)
    static let shift = ShortcutModifiers(rawValue: 1 << 2)
    static let option = ShortcutModifiers(rawValue: 1 << 3)
    static let function = ShortcutModifiers(rawValue: 1 << 4)
}

enum ShortcutEventType {
    case flagsChanged
    case keyDown
    case keyUp
}

struct ShortcutEvent: Equatable {
    let type: ShortcutEventType
    let keyCode: Int64
    let modifiers: ShortcutModifiers
    let isRepeat: Bool
}

enum ShortcutAction: Equatable {
    case none
    case start
    case finish
    case cancel
}

struct ShortcutInterpreter {
    private enum KeyCode {
        static let space: Int64 = 49
        static let escape: Int64 = 53
        static let rightOption: Int64 = 61
        static let function: Int64 = 63
    }

    var settings: ShortcutSettings {
        didSet {
            isShortcutDown = false
            isActive = false
        }
    }

    private(set) var isShortcutDown = false
    private(set) var isActive = false

    init(settings: ShortcutSettings = .default) {
        self.settings = settings
    }

    mutating func interpret(_ event: ShortcutEvent) -> ShortcutAction {
        if event.type == .keyDown, event.keyCode == KeyCode.escape {
            isActive = false
            return .cancel
        }

        switch settings.behavior {
        case .pushToTalk:
            return interpretPushToTalk(event)
        case .toggle:
            return interpretToggle(event)
        }
    }

    private mutating func interpretPushToTalk(_ event: ShortcutEvent) -> ShortcutAction {
        if isShortcutUpEvent(event) {
            guard isShortcutDown else { return .none }
            isShortcutDown = false
            guard isActive else { return .none }
            isActive = false
            return .finish
        }

        if isShortcutDownEvent(event) {
            guard !isShortcutDown, !event.isRepeat else { return .none }
            isShortcutDown = true
            isActive = true
            return .start
        }

        return .none
    }

    private mutating func interpretToggle(_ event: ShortcutEvent) -> ShortcutAction {
        if isShortcutUpEvent(event) {
            isShortcutDown = false
            return .none
        }

        if isShortcutDownEvent(event) {
            guard !isShortcutDown, !event.isRepeat else { return .none }
            isShortcutDown = true
            if isActive {
                isActive = false
                return .finish
            } else {
                isActive = true
                return .start
            }
        }

        return .none
    }

    private func isShortcutDownEvent(_ event: ShortcutEvent) -> Bool {
        switch settings.option {
        case .rightOption:
            return event.type == .flagsChanged
                && event.keyCode == KeyCode.rightOption
                && event.modifiers.contains(.option)
        case .fn:
            return event.type == .flagsChanged
                && event.keyCode == KeyCode.function
                && event.modifiers.contains(.function)
        case .controlSpace:
            return event.type == .keyDown
                && event.keyCode == KeyCode.space
                && event.modifiers == [.control]
        case .commandShiftSpace:
            return event.type == .keyDown
                && event.keyCode == KeyCode.space
                && event.modifiers == [.command, .shift]
        }
    }

    private func isShortcutUpEvent(_ event: ShortcutEvent) -> Bool {
        switch settings.option {
        case .rightOption:
            return event.type == .flagsChanged && event.keyCode == KeyCode.rightOption && isShortcutDown
        case .fn:
            return event.type == .flagsChanged && event.keyCode == KeyCode.function && isShortcutDown
        case .controlSpace:
            return event.type == .keyUp && event.keyCode == KeyCode.space
        case .commandShiftSpace:
            return event.type == .keyUp && event.keyCode == KeyCode.space
        }
    }
}

enum ShortcutStartResult {
    case started
    case eventTapUnavailable
}

final class ShortcutManager {
    typealias EventTapFactory = (CGEventMask, @escaping CGEventTapCallBack, UnsafeMutableRawPointer?) -> CFMachPort?

    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    private(set) var isRunning = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var interpreter: ShortcutInterpreter
    private let eventTapFactory: EventTapFactory

    init(
        settings: ShortcutSettings = .default,
        eventTapFactory: @escaping EventTapFactory = ShortcutManager.createEventTap
    ) {
        interpreter = ShortcutInterpreter(settings: settings)
        self.eventTapFactory = eventTapFactory
    }

    func update(settings: ShortcutSettings) {
        interpreter.settings = settings
    }

    func start() -> ShortcutStartResult {
        guard !isRunning else {
            return .started
        }

        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { proxy, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let manager = Unmanaged<ShortcutManager>.fromOpaque(refcon).takeUnretainedValue()
            return manager.handle(proxy: proxy, type: type, event: event)
        }

        eventTap = eventTapFactory(CGEventMask(mask), callback, Unmanaged.passUnretained(self).toOpaque())

        guard let eventTap else {
            return .eventTapUnavailable
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        isRunning = true
        return .started
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
        isRunning = false
    }

    private static func createEventTap(
        eventsOfInterest: CGEventMask,
        callback: @escaping CGEventTapCallBack,
        userInfo: UnsafeMutableRawPointer?
    ) -> CFMachPort? {
        CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventsOfInterest,
            callback: callback,
            userInfo: userInfo
        )
    }

    private func handle(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let shortcutEvent = ShortcutEvent(type: type, event: event) else {
            return Unmanaged.passUnretained(event)
        }

        let action = interpreter.interpret(shortcutEvent)
        switch action {
        case .none:
            break
        case .start:
            onStart?()
        case .finish:
            onFinish?()
        case .cancel:
            onCancel?()
        }

        if action != .none, shortcutEvent.type != .flagsChanged {
            return nil
        }

        return Unmanaged.passUnretained(event)
    }
}

private extension ShortcutEvent {
    init?(type: CGEventType, event: CGEvent) {
        let eventType: ShortcutEventType
        switch type {
        case .flagsChanged:
            eventType = .flagsChanged
        case .keyDown:
            eventType = .keyDown
        case .keyUp:
            eventType = .keyUp
        default:
            return nil
        }

        self.init(
            type: eventType,
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            modifiers: ShortcutModifiers(event.flags),
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )
    }
}

private extension ShortcutModifiers {
    init(_ flags: CGEventFlags) {
        var modifiers: ShortcutModifiers = []
        if flags.contains(.maskControl) {
            modifiers.insert(.control)
        }
        if flags.contains(.maskCommand) {
            modifiers.insert(.command)
        }
        if flags.contains(.maskShift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.maskAlternate) {
            modifiers.insert(.option)
        }
        if flags.contains(.maskSecondaryFn) {
            modifiers.insert(.function)
        }
        self = modifiers
    }
}
