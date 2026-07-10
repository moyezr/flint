import XCTest
@testable import Flint

@MainActor
final class AppModeSettingsModelTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var tempRoot: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "FlintTests.AppModeSettingsModel.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-app-mode-settings-model-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        databaseURL = tempRoot.appendingPathComponent("History.sqlite")
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        databaseURL = nil
        tempRoot = nil
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testTogglePersistsOptInAndNotifiesCoordinator() {
        var receivedSettings: [AppSettings] = []
        let model = makeModel { receivedSettings.append($0) }

        XCTAssertFalse(model.settings.appAwareModesEnabled)

        model.setAppAwareModesEnabled(true)

        XCTAssertTrue(model.settings.appAwareModesEnabled)
        XCTAssertTrue(AppSettingsStore(defaults: defaults).load().appAwareModesEnabled)
        XCTAssertEqual(receivedSettings.last?.appAwareModesEnabled, true)
    }

    func testAddUpdateAndDeleteRule() {
        let model = makeModel()
        model.newBundleID = " com.tinyspeck.slackmacgap "
        model.newMode = .message

        model.addRule()

        let rule = try! XCTUnwrap(model.rules.first)
        XCTAssertEqual(rule.appBundleID, "com.tinyspeck.slackmacgap")
        XCTAssertEqual(rule.mode, .message)
        XCTAssertTrue(rule.enabled)

        model.setMode(.prompt, for: rule)
        let updatedModeRule = try! XCTUnwrap(model.rules.first)
        XCTAssertEqual(updatedModeRule.mode, .prompt)

        model.setEnabled(false, for: updatedModeRule)
        let disabledRule = try! XCTUnwrap(model.rules.first)
        XCTAssertFalse(disabledRule.enabled)

        model.delete(disabledRule)
        XCTAssertTrue(model.rules.isEmpty)
    }

    func testInvalidRuleLeavesRulesUnchangedAndSurfacesError() {
        let model = makeModel()
        model.newBundleID = "  "

        model.addRule()

        XCTAssertTrue(model.rules.isEmpty)
        XCTAssertEqual(model.errorMessage, "An app mode rule must have an app bundle ID or URL pattern.")
    }

    private func makeModel(
        onSettingsChanged: @escaping (AppSettings) -> Void = { _ in }
    ) -> AppModeSettingsModel {
        AppModeSettingsModel(
            settingsStore: AppSettingsStore(defaults: defaults),
            ruleStore: AppModeRuleStore(databaseURL: databaseURL),
            onSettingsChanged: onSettingsChanged
        )
    }
}
