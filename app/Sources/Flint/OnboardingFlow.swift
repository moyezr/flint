import Combine
import Foundation

enum OnboardingStep: CaseIterable, Equatable {
    case welcome
    case privacy
    case shortcut
    case permissions
    case model
    case testDictation

    var title: String {
        switch self {
        case .welcome:
            return "Welcome to Flint"
        case .privacy:
            return "Privacy Promise"
        case .shortcut:
            return "Choose Shortcut"
        case .permissions:
            return "Grant Permissions"
        case .model:
            return "Choose Model"
        case .testDictation:
            return "Test Dictation"
        }
    }
}

@MainActor
final class OnboardingFlow: ObservableObject {
    typealias PermissionSnapshotProvider = () -> PermissionSnapshot
    typealias PermissionPromptAction = () async -> Void
    typealias ModelInstalledProvider = (ModelTier) -> Bool
    typealias ModelDownloadAction = (ModelTier) async throws -> Void
    typealias SettingsChangedAction = (AppSettings) -> Void

    @Published private(set) var currentStep: OnboardingStep
    @Published private(set) var settings: AppSettings
    @Published private(set) var permissionSnapshot: PermissionSnapshot
    @Published private(set) var isPromptingForPermissions = false
    @Published private(set) var isDownloadingModel = false
    @Published private(set) var modelDownloadStatus = ""

    private let store: AppSettingsStore
    private let permissionSnapshotProvider: PermissionSnapshotProvider
    private let permissionPromptAction: PermissionPromptAction
    private let modelInstalledProvider: ModelInstalledProvider
    private let modelDownloadAction: ModelDownloadAction
    private let onPermissionsPromptCompleted: (() -> Void)?
    private let onSettingsChanged: SettingsChangedAction?
    private let onComplete: (() -> Void)?

    init(
        store: AppSettingsStore,
        permissionSnapshotProvider: @escaping PermissionSnapshotProvider,
        permissionPromptAction: @escaping PermissionPromptAction,
        modelInstalledProvider: @escaping ModelInstalledProvider,
        modelDownloadAction: @escaping ModelDownloadAction,
        onPermissionsPromptCompleted: (() -> Void)? = nil,
        onSettingsChanged: SettingsChangedAction? = nil,
        onComplete: (() -> Void)? = nil,
        initialStep: OnboardingStep = .welcome
    ) {
        self.store = store
        self.permissionSnapshotProvider = permissionSnapshotProvider
        self.permissionPromptAction = permissionPromptAction
        self.modelInstalledProvider = modelInstalledProvider
        self.modelDownloadAction = modelDownloadAction
        self.onPermissionsPromptCompleted = onPermissionsPromptCompleted
        self.onSettingsChanged = onSettingsChanged
        self.onComplete = onComplete
        self.currentStep = initialStep
        self.settings = store.load()
        self.permissionSnapshot = permissionSnapshotProvider()
    }

    var canGoBack: Bool {
        currentStep != OnboardingStep.allCases.first && !isPromptingForPermissions && !isDownloadingModel
    }

    var isFinalStep: Bool {
        currentStep == OnboardingStep.allCases.last
    }

    var canAdvance: Bool {
        guard !isPromptingForPermissions, !isDownloadingModel else {
            return false
        }

        switch currentStep {
        case .permissions:
            return permissionSnapshot.missingCount == 0
        case .model:
            return isSelectedModelInstalled
        case .testDictation:
            return canFinish
        default:
            return true
        }
    }

    var canFinish: Bool {
        isFinalStep
            && permissionSnapshot.missingCount == 0
            && isSelectedModelInstalled
            && !isPromptingForPermissions
            && !isDownloadingModel
    }

    var isSelectedModelInstalled: Bool {
        modelInstalledProvider(settings.selectedModelTier)
    }

    func next() {
        guard canAdvance else { return }
        guard let index = Self.stepIndex(currentStep),
              index < OnboardingStep.allCases.index(before: OnboardingStep.allCases.endIndex) else {
            return
        }
        currentStep = OnboardingStep.allCases[index + 1]
        refreshPermissionSnapshot()
    }

    func back() {
        guard canGoBack else { return }
        guard let index = Self.stepIndex(currentStep), index > OnboardingStep.allCases.startIndex else {
            return
        }
        currentStep = OnboardingStep.allCases[index - 1]
        refreshPermissionSnapshot()
    }

    func selectShortcut(_ option: ShortcutOption) {
        settings.shortcutSettings.option = option
        store.saveShortcutSettings(settings.shortcutSettings)
        onSettingsChanged?(settings)
    }

    func selectShortcutBehavior(_ behavior: ShortcutInputBehavior) {
        settings.shortcutSettings.behavior = behavior
        store.saveShortcutSettings(settings.shortcutSettings)
        onSettingsChanged?(settings)
    }

    func selectModelTier(_ tier: ModelTier) {
        settings.selectedModelTier = tier
        modelDownloadStatus = ""
        store.saveSelectedModelTier(tier)
        onSettingsChanged?(settings)
    }

    func refreshPermissionSnapshot() {
        permissionSnapshot = permissionSnapshotProvider()
    }

    func promptForPermissions() async {
        guard !isPromptingForPermissions else { return }
        isPromptingForPermissions = true
        await permissionPromptAction()
        onPermissionsPromptCompleted?()
        isPromptingForPermissions = false
        refreshPermissionSnapshot()
    }

    func downloadSelectedModel() async {
        guard !isDownloadingModel else { return }
        isDownloadingModel = true
        modelDownloadStatus = ""

        do {
            try await modelDownloadAction(settings.selectedModelTier)
            modelDownloadStatus = "\(settings.selectedModelTier.displayName) model is ready."
        } catch {
            modelDownloadStatus = "Model download failed: \(error.localizedDescription)"
        }

        isDownloadingModel = false
    }

    func finish() {
        guard canFinish else { return }
        settings.hasCompletedOnboarding = true
        store.saveHasCompletedOnboarding(true)
        onComplete?()
    }

    private static func stepIndex(_ step: OnboardingStep) -> Int? {
        OnboardingStep.allCases.firstIndex(of: step)
    }
}
