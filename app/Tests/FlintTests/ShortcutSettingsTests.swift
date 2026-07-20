import XCTest
@testable import Flint

final class ShortcutSettingsTests: XCTestCase {
    private enum KeyCode {
        static let space: Int64 = 49
        static let escape: Int64 = 53
        static let leftOption: Int64 = 58
        static let rightOption: Int64 = 61
        static let function: Int64 = 63
    }

    func testShortcutMatchingForSupportedOptions() {
        var rightOption = ShortcutInterpreter(settings: ShortcutSettings(option: .rightOption, behavior: .pushToTalk))
        XCTAssertEqual(
            rightOption.interpret(event(.flagsChanged, keyCode: KeyCode.rightOption, modifiers: [.option])),
            .start
        )

        var controlSpace = ShortcutInterpreter(settings: ShortcutSettings(option: .controlSpace, behavior: .pushToTalk))
        XCTAssertEqual(
            controlSpace.interpret(event(.keyDown, keyCode: KeyCode.space, modifiers: [.control])),
            .start
        )

        var commandShiftSpace = ShortcutInterpreter(settings: ShortcutSettings(option: .commandShiftSpace, behavior: .pushToTalk))
        XCTAssertEqual(
            commandShiftSpace.interpret(event(.keyDown, keyCode: KeyCode.space, modifiers: [.command, .shift])),
            .start
        )
    }

    func testShortcutMatchingRequiresExactModifiersForSpaceShortcuts() {
        var controlSpace = ShortcutInterpreter(settings: ShortcutSettings(option: .controlSpace, behavior: .pushToTalk))
        XCTAssertEqual(
            controlSpace.interpret(event(.keyDown, keyCode: KeyCode.space, modifiers: [.control, .shift])),
            .none
        )

        var commandShiftSpace = ShortcutInterpreter(settings: ShortcutSettings(option: .commandShiftSpace, behavior: .pushToTalk))
        XCTAssertEqual(
            commandShiftSpace.interpret(event(.keyDown, keyCode: KeyCode.space, modifiers: [.command])),
            .none
        )
    }

    func testShortcutSettingsStoreDefaultsToRightOptionPushToTalkForMissingOrUnknownValues() {
        let suiteName = "ShortcutSettingsStoreTests.missing"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ShortcutSettingsStore(defaults: defaults, shortcutKey: "shortcut", behaviorKey: "behavior")

        XCTAssertEqual(store.load(), .default)

        defaults.set("unknown", forKey: "shortcut")
        defaults.set("unknown", forKey: "behavior")
        XCTAssertEqual(store.load(), .default)
    }

    func testShortcutSettingsStorePersistsSelectedShortcutAndBehavior() {
        let suiteName = "ShortcutSettingsStoreTests.persisted"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let store = ShortcutSettingsStore(defaults: defaults, shortcutKey: "shortcut", behaviorKey: "behavior")
        let settings = ShortcutSettings(option: .commandShiftSpace, behavior: .toggle)

        store.save(settings)

        XCTAssertEqual(store.load(), settings)
    }

    func testPushToTalkTransitionsStartOnDownAndFinishOnRelease() {
        var interpreter = ShortcutInterpreter(settings: ShortcutSettings(option: .controlSpace, behavior: .pushToTalk))

        XCTAssertEqual(interpreter.interpret(event(.keyDown, keyCode: KeyCode.space, modifiers: [.control])), .start)
        XCTAssertEqual(interpreter.interpret(event(.keyDown, keyCode: KeyCode.space, modifiers: [.control], isRepeat: true)), .none)
        XCTAssertEqual(interpreter.interpret(event(.keyUp, keyCode: KeyCode.space)), .finish)
        XCTAssertEqual(interpreter.interpret(event(.keyUp, keyCode: KeyCode.space)), .none)
    }

    func testRightOptionPushToTalkDefaultTransitionsStillWork() {
        var interpreter = ShortcutInterpreter()

        XCTAssertEqual(interpreter.interpret(event(.flagsChanged, keyCode: KeyCode.rightOption, modifiers: [.option])), .start)
        XCTAssertEqual(interpreter.interpret(event(.flagsChanged, keyCode: KeyCode.rightOption)), .finish)
    }

    func testFnPushToTalkStartsAndFinishesOnModifierTransitions() {
        var interpreter = ShortcutInterpreter(settings: ShortcutSettings(option: .fn, behavior: .pushToTalk))

        XCTAssertEqual(
            interpreter.interpret(event(.flagsChanged, keyCode: KeyCode.function, modifiers: [.function])),
            .start
        )
        XCTAssertEqual(interpreter.interpret(event(.flagsChanged, keyCode: KeyCode.function)), .finish)
    }

    func testFnToggleRequiresAReleaseBeforeSecondPress() {
        var interpreter = ShortcutInterpreter(settings: ShortcutSettings(option: .fn, behavior: .toggle))

        XCTAssertEqual(
            interpreter.interpret(event(.flagsChanged, keyCode: KeyCode.function, modifiers: [.function])),
            .start
        )
        XCTAssertEqual(
            interpreter.interpret(event(.flagsChanged, keyCode: KeyCode.function, modifiers: [.function])),
            .none
        )
        XCTAssertEqual(interpreter.interpret(event(.flagsChanged, keyCode: KeyCode.function)), .none)
        XCTAssertEqual(
            interpreter.interpret(event(.flagsChanged, keyCode: KeyCode.function, modifiers: [.function])),
            .finish
        )
    }

    func testLeftOptionDoesNotStartRightOptionShortcut() {
        var interpreter = ShortcutInterpreter()

        XCTAssertEqual(interpreter.interpret(event(.flagsChanged, keyCode: KeyCode.leftOption, modifiers: [.option])), .none)
        XCTAssertFalse(interpreter.isActive)
        XCTAssertFalse(interpreter.isShortcutDown)
    }

    func testRightOptionReleaseFinishesWhenAggregateOptionModifierRemainsSet() {
        var interpreter = ShortcutInterpreter()

        XCTAssertEqual(interpreter.interpret(event(.flagsChanged, keyCode: KeyCode.rightOption, modifiers: [.option])), .start)
        XCTAssertEqual(interpreter.interpret(event(.flagsChanged, keyCode: KeyCode.rightOption, modifiers: [.option])), .finish)
        XCTAssertFalse(interpreter.isActive)
        XCTAssertFalse(interpreter.isShortcutDown)
    }

    func testShortcutManagerStartIsIdempotentAndExposesRunningState() throws {
        var eventTapCreations = 0
        let manager = ShortcutManager { _, _, _ in
            eventTapCreations += 1
            return try! Self.makeMachPort()
        }

        XCTAssertFalse(manager.isRunning)
        XCTAssertEqual(manager.start(), .started)
        XCTAssertTrue(manager.isRunning)
        XCTAssertEqual(manager.start(), .started)
        XCTAssertTrue(manager.isRunning)
        XCTAssertEqual(eventTapCreations, 1)

        manager.stop()
        XCTAssertFalse(manager.isRunning)
    }

    func testToggleTransitionsStartAndFinishOnRepeatedShortcutPresses() {
        var interpreter = ShortcutInterpreter(settings: ShortcutSettings(option: .commandShiftSpace, behavior: .toggle))

        XCTAssertEqual(interpreter.interpret(event(.keyDown, keyCode: KeyCode.space, modifiers: [.command, .shift])), .start)
        XCTAssertEqual(interpreter.interpret(event(.keyDown, keyCode: KeyCode.space, modifiers: [.command, .shift], isRepeat: true)), .none)
        XCTAssertEqual(interpreter.interpret(event(.keyUp, keyCode: KeyCode.space)), .none)
        XCTAssertEqual(interpreter.interpret(event(.keyDown, keyCode: KeyCode.space, modifiers: [.command, .shift])), .finish)
        XCTAssertEqual(interpreter.interpret(event(.keyUp, keyCode: KeyCode.space)), .none)
    }

    func testEscapeCancelsActiveShortcutInterpretation() {
        var interpreter = ShortcutInterpreter(settings: ShortcutSettings(option: .controlSpace, behavior: .pushToTalk))

        XCTAssertEqual(interpreter.interpret(event(.keyDown, keyCode: KeyCode.space, modifiers: [.control])), .start)
        XCTAssertEqual(interpreter.interpret(event(.keyDown, keyCode: KeyCode.escape)), .cancel)
        XCTAssertEqual(interpreter.interpret(event(.keyUp, keyCode: KeyCode.space)), .none)
    }

    private func event(
        _ type: ShortcutEventType,
        keyCode: Int64,
        modifiers: ShortcutModifiers = [],
        isRepeat: Bool = false
    ) -> ShortcutEvent {
        ShortcutEvent(type: type, keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat)
    }

    private static func makeMachPort() throws -> CFMachPort {
        var context = CFMachPortContext()
        return try XCTUnwrap(CFMachPortCreate(kCFAllocatorDefault, { _, _, _, _ in }, &context, nil))
    }
}
