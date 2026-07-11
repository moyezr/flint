import XCTest
@testable import Flint

final class AppModeResolverTests: XCTestCase {
    private let resolver = AppModeResolver()

    func testFallsBackToManualWhenAppAwareDisabled() {
        let mode = resolver.resolve(
            context: AppModeResolutionContext(
                appAwareModesEnabled: false,
                manualMode: .clean,
                activeAppBundleID: "com.apple.mail"
            ),
            rules: [makeRule(appBundleID: "com.apple.mail", mode: .email)]
        )

        XCTAssertEqual(mode, .clean)
    }

    func testFallsBackToManualWithoutActiveBundleID() {
        let mode = resolver.resolve(
            context: AppModeResolutionContext(
                appAwareModesEnabled: true,
                manualMode: .polished,
                activeAppBundleID: nil
            ),
            rules: [makeRule(appBundleID: "com.apple.mail", mode: .email)]
        )

        XCTAssertEqual(mode, .polished)
    }

    func testExactEnabledBundleIDMatchSelectsRuleMode() {
        let mode = resolver.resolve(
            context: AppModeResolutionContext(
                appAwareModesEnabled: true,
                manualMode: .clean,
                activeAppBundleID: "com.apple.mail"
            ),
            rules: [makeRule(appBundleID: "com.apple.mail", mode: .email)]
        )

        XCTAssertEqual(mode, .email)
    }

    func testDisabledAndNonMatchingRulesFallBackToManual() {
        let mode = resolver.resolve(
            context: AppModeResolutionContext(
                appAwareModesEnabled: true,
                manualMode: .message,
                activeAppBundleID: "com.apple.mail"
            ),
            rules: [
                makeRule(appBundleID: "com.apple.mail", mode: .email, enabled: false),
                makeRule(appBundleID: "com.apple.Notes", mode: .prompt)
            ]
        )

        XCTAssertEqual(mode, .message)
    }

    func testURLPatternsDoNotMatchWithoutBundleID() {
        let mode = resolver.resolve(
            context: AppModeResolutionContext(
                appAwareModesEnabled: true,
                manualMode: .clean,
                activeAppBundleID: "com.apple.Safari"
            ),
            rules: [makeRule(appBundleID: nil, urlPattern: "https://mail.example.com", mode: .email)]
        )

        XCTAssertEqual(mode, .clean)
    }

    func testEarliestCreatedThenLowestIDWinsPrecedence() {
        let later = makeRule(
            id: 1,
            appBundleID: "com.apple.mail",
            mode: .email,
            createdAt: Date(timeIntervalSince1970: 200)
        )
        let earlierHighID = makeRule(
            id: 5,
            appBundleID: "com.apple.mail",
            mode: .message,
            createdAt: Date(timeIntervalSince1970: 100)
        )
        let earlierLowID = makeRule(
            id: 4,
            appBundleID: "com.apple.mail",
            mode: .prompt,
            createdAt: Date(timeIntervalSince1970: 100)
        )

        let mode = resolver.resolve(
            context: AppModeResolutionContext(
                appAwareModesEnabled: true,
                manualMode: .clean,
                activeAppBundleID: "com.apple.mail"
            ),
            rules: [later, earlierHighID, earlierLowID]
        )

        XCTAssertEqual(mode, .prompt)
    }

    private func makeRule(
        id: Int64 = 1,
        appBundleID: String?,
        urlPattern: String? = nil,
        mode: CleanupMode,
        enabled: Bool = true,
        createdAt: Date = Date(timeIntervalSince1970: 100)
    ) -> AppModeRule {
        AppModeRule(
            id: id,
            appBundleID: appBundleID,
            urlPattern: urlPattern,
            mode: mode,
            enabled: enabled,
            createdAt: createdAt,
            updatedAt: createdAt
        )
    }
}
