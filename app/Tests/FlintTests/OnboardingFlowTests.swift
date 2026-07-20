import XCTest
@testable import Flint

@MainActor
final class OnboardingFlowTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "FlintTests.OnboardingFlow.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    func testOrderedStepProgressionAndBackNextBounds() {
        let flow = makeFlow()

        XCTAssertEqual(flow.currentStep, .welcome)
        XCTAssertFalse(flow.canGoBack)

        flow.next()
        XCTAssertEqual(flow.currentStep, .privacy)
        flow.next()
        XCTAssertEqual(flow.currentStep, .shortcut)
        flow.next()
        XCTAssertEqual(flow.currentStep, .permissions)
        flow.next()
        XCTAssertEqual(flow.currentStep, .model)
        flow.next()
        XCTAssertEqual(flow.currentStep, .testDictation)
        XCTAssertTrue(flow.isFinalStep)

        flow.next()
        XCTAssertEqual(flow.currentStep, .testDictation)

        flow.back()
        XCTAssertEqual(flow.currentStep, .model)
        flow.back()
        XCTAssertEqual(flow.currentStep, .permissions)
        flow.back()
        XCTAssertEqual(flow.currentStep, .shortcut)
        flow.back()
        XCTAssertEqual(flow.currentStep, .privacy)
        flow.back()
        XCTAssertEqual(flow.currentStep, .welcome)
        flow.back()
        XCTAssertEqual(flow.currentStep, .welcome)
    }

    func testFreshFlowRestartsAtWelcomeWithoutDiscardingExistingChoices() {
        let store = AppSettingsStore(defaults: defaults)
        store.saveHasCompletedOnboarding(true)
        store.saveSelectedModelTier(.accurate)
        store.saveShortcutSettings(ShortcutSettings(option: .commandShiftSpace, behavior: .toggle))

        store.saveHasCompletedOnboarding(false)
        let flow = makeFlow()

        XCTAssertEqual(flow.currentStep, .welcome)
        XCTAssertFalse(flow.settings.hasCompletedOnboarding)
        XCTAssertEqual(flow.settings.selectedModelTier, .accurate)
        XCTAssertEqual(
            flow.settings.shortcutSettings,
            ShortcutSettings(option: .commandShiftSpace, behavior: .toggle)
        )
    }

    func testFinishDoesNotCompleteWhenPermissionsAreMissing() {
        var completionCount = 0
        let flow = makeFlow(
            snapshot: missingPermissionSnapshot(),
            onComplete: { completionCount += 1 }
        )

        flow.finish()

        XCTAssertFalse(AppSettingsStore(defaults: defaults).load().hasCompletedOnboarding)
        XCTAssertFalse(flow.settings.hasCompletedOnboarding)
        XCTAssertEqual(completionCount, 0)
    }

    func testFinishMarksOnboardingCompleteWhenPermissionsAndModelAreReady() {
        var completionCount = 0
        let flow = makeFlow(onComplete: { completionCount += 1 })
        while !flow.isFinalStep {
            flow.next()
        }

        flow.finish()

        XCTAssertTrue(AppSettingsStore(defaults: defaults).load().hasCompletedOnboarding)
        XCTAssertTrue(flow.settings.hasCompletedOnboarding)
        XCTAssertEqual(completionCount, 1)
    }

    func testShortcutSelectionPersistsImmediately() {
        var changedSettings: [AppSettings] = []
        let notifyingFlow = makeFlow(onSettingsChanged: { changedSettings.append($0) })

        notifyingFlow.selectShortcut(.commandShiftSpace)
        notifyingFlow.selectShortcutBehavior(.toggle)

        let settings = AppSettingsStore(defaults: defaults).load()
        XCTAssertEqual(settings.shortcutSettings, ShortcutSettings(option: .commandShiftSpace, behavior: .toggle))
        XCTAssertEqual(notifyingFlow.settings.shortcutSettings, settings.shortcutSettings)
        XCTAssertEqual(changedSettings.map(\.shortcutSettings), [
            ShortcutSettings(option: .commandShiftSpace, behavior: .pushToTalk),
            ShortcutSettings(option: .commandShiftSpace, behavior: .toggle)
        ])
    }

    func testModelSelectionPersistsImmediately() {
        let flow = makeFlow()

        flow.selectModelTier(.accurate)

        let settings = AppSettingsStore(defaults: defaults).load()
        XCTAssertEqual(settings.selectedModelTier, .accurate)
        XCTAssertEqual(flow.settings.selectedModelTier, .accurate)
    }

    func testRecommendedModelIsSelectedAndPersistedForFreshOnboarding() {
        let store = AppSettingsStore(defaults: defaults)
        var changedSettings: [AppSettings] = []
        let flow = OnboardingFlow(
            store: store,
            permissionSnapshotProvider: { self.readyPermissionSnapshot() },
            permissionPromptAction: {},
            modelInstalledProvider: { _ in true },
            modelDownloadAction: { _, _ in },
            onSettingsChanged: { changedSettings.append($0) },
            recommendedModelTier: .accurate,
            allowsModelSelection: false
        )

        XCTAssertEqual(flow.settings.selectedModelTier, .accurate)
        XCTAssertEqual(store.load().selectedModelTier, .accurate)
        XCTAssertFalse(flow.allowsModelSelection)
        XCTAssertEqual(changedSettings.map(\.selectedModelTier), [.accurate])

        flow.selectModelTier(.fast)
        XCTAssertEqual(flow.settings.selectedModelTier, .accurate)
    }

    func testRecommendedModelDoesNotReplaceAnExistingSelection() {
        let store = AppSettingsStore(defaults: defaults)
        store.saveSelectedModelTier(.fast)

        let flow = OnboardingFlow(
            store: store,
            permissionSnapshotProvider: { self.readyPermissionSnapshot() },
            permissionPromptAction: {},
            modelInstalledProvider: { _ in true },
            modelDownloadAction: { _, _ in },
            recommendedModelTier: .accurate,
            allowsModelSelection: false
        )

        XCTAssertEqual(flow.settings.selectedModelTier, .fast)
    }

    func testPermissionPromptUsesInjectedActionAndRefreshesSnapshot() async {
        var promptCount = 0
        var snapshot = missingPermissionSnapshot()
        let flow = makeFlow(
            snapshotProvider: { snapshot },
            permissionPromptAction: {
                promptCount += 1
                snapshot = PermissionSnapshot(statuses: [
                    PermissionStatus(kind: .microphone, readiness: .ready),
                    PermissionStatus(kind: .accessibility, readiness: .ready),
                    PermissionStatus(kind: .inputMonitoring, readiness: .ready)
                ])
            }
        )

        XCTAssertEqual(flow.permissionSnapshot.missingCount, 3)

        await flow.promptForPermissions()

        XCTAssertEqual(promptCount, 1)
        XCTAssertEqual(flow.permissionSnapshot.missingCount, 0)
        XCTAssertFalse(flow.isPromptingForPermissions)
    }

    func testPermissionPromptNotifiesListenerRecoveryAfterRequestCompletes() async {
        var didRequestPermissions = false
        var didNotifyRecovery = false
        let flow = makeFlow(
            snapshotProvider: { PermissionSnapshot(statuses: []) },
            permissionPromptAction: {
                didRequestPermissions = true
            },
            onPermissionsPromptCompleted: {
                XCTAssertTrue(didRequestPermissions)
                didNotifyRecovery = true
            }
        )

        await flow.promptForPermissions()

        XCTAssertTrue(didNotifyRecovery)
    }

    func testPermissionsArePromptedAutomaticallyOnceWhenStepAppears() async {
        var promptCount = 0
        let flow = makeFlow(
            snapshotProvider: { self.missingPermissionSnapshot() },
            permissionPromptAction: { promptCount += 1 }
        )

        await flow.promptForPermissionsIfNeeded()
        XCTAssertEqual(promptCount, 0)

        flow.next()
        flow.next()
        flow.next()
        XCTAssertEqual(flow.currentStep, .permissions)

        await flow.promptForPermissionsIfNeeded()
        await flow.promptForPermissionsIfNeeded()

        XCTAssertEqual(promptCount, 1)
    }

    func testAutomaticPermissionPromptSkipsReadyPermissions() async {
        var promptCount = 0
        let flow = makeFlow(
            snapshotProvider: { self.readyPermissionSnapshot() },
            permissionPromptAction: { promptCount += 1 }
        )

        flow.next()
        flow.next()
        flow.next()
        await flow.promptForPermissionsIfNeeded()

        XCTAssertEqual(promptCount, 0)
    }

    func testCannotAdvancePastPermissionsUntilAllPermissionsAreReady() {
        var snapshot = missingPermissionSnapshot()
        let flow = makeFlow(
            snapshotProvider: { snapshot },
            permissionPromptAction: {}
        )

        flow.next()
        flow.next()
        flow.next()
        XCTAssertEqual(flow.currentStep, .permissions)
        XCTAssertFalse(flow.canAdvance)

        flow.next()
        XCTAssertEqual(flow.currentStep, .permissions)

        snapshot = readyPermissionSnapshot()
        flow.refreshPermissionSnapshot()

        XCTAssertTrue(flow.canAdvance)
        flow.next()
        XCTAssertEqual(flow.currentStep, .model)
    }

    func testCannotAdvancePastModelUntilSelectedModelIsInstalled() async {
        var installedTiers: [ModelTier] = [.fast, .accurate]
        let flow = makeFlow(
            modelInstalledProvider: { installedTiers.contains($0) },
            modelDownloadAction: { tier, reportProgress in
                reportProgress(0.35)
                reportProgress(0.8)
                installedTiers.append(tier)
            }
        )

        moveToModelStep(flow)
        XCTAssertEqual(flow.settings.selectedModelTier, .balanced)
        XCTAssertFalse(flow.canAdvance)

        flow.next()
        XCTAssertEqual(flow.currentStep, .model)

        await flow.downloadSelectedModel()

        XCTAssertTrue(flow.canAdvance)
        XCTAssertEqual(flow.modelDownloadProgress, 1)
        XCTAssertEqual(flow.modelDownloadStatus, "Balanced model is ready.")
        flow.next()
        XCTAssertEqual(flow.currentStep, .testDictation)
    }

    private func makeFlow(
        snapshot: PermissionSnapshot = PermissionSnapshot(statuses: []),
        modelInstalledProvider: @escaping (ModelTier) -> Bool = { _ in true },
        modelDownloadAction: @escaping OnboardingFlow.ModelDownloadAction = { _, _ in },
        onPermissionsPromptCompleted: (() -> Void)? = nil,
        onSettingsChanged: ((AppSettings) -> Void)? = nil,
        onComplete: (() -> Void)? = nil
    ) -> OnboardingFlow {
        makeFlow(
            snapshotProvider: { snapshot },
            permissionPromptAction: {},
            modelInstalledProvider: modelInstalledProvider,
            modelDownloadAction: modelDownloadAction,
            onPermissionsPromptCompleted: onPermissionsPromptCompleted,
            onSettingsChanged: onSettingsChanged,
            onComplete: onComplete
        )
    }

    private func makeFlow(
        snapshotProvider: @escaping () -> PermissionSnapshot,
        permissionPromptAction: @escaping () async -> Void,
        modelInstalledProvider: @escaping (ModelTier) -> Bool = { _ in true },
        modelDownloadAction: @escaping OnboardingFlow.ModelDownloadAction = { _, _ in },
        onPermissionsPromptCompleted: (() -> Void)? = nil,
        onSettingsChanged: ((AppSettings) -> Void)? = nil,
        onComplete: (() -> Void)? = nil
    ) -> OnboardingFlow {
        OnboardingFlow(
            store: AppSettingsStore(defaults: defaults),
            permissionSnapshotProvider: snapshotProvider,
            permissionPromptAction: permissionPromptAction,
            modelInstalledProvider: modelInstalledProvider,
            modelDownloadAction: modelDownloadAction,
            onPermissionsPromptCompleted: onPermissionsPromptCompleted,
            onSettingsChanged: onSettingsChanged,
            onComplete: onComplete
        )
    }

    private func moveToModelStep(_ flow: OnboardingFlow) {
        while flow.currentStep != .model {
            flow.next()
        }
    }

    private func missingPermissionSnapshot() -> PermissionSnapshot {
        PermissionSnapshot(statuses: [
            PermissionStatus(kind: .microphone, readiness: .notDetermined),
            PermissionStatus(kind: .accessibility, readiness: .denied),
            PermissionStatus(kind: .inputMonitoring, readiness: .denied)
        ])
    }

    private func readyPermissionSnapshot() -> PermissionSnapshot {
        PermissionSnapshot(statuses: [
            PermissionStatus(kind: .microphone, readiness: .ready),
            PermissionStatus(kind: .accessibility, readiness: .ready),
            PermissionStatus(kind: .inputMonitoring, readiness: .ready)
        ])
    }
}
