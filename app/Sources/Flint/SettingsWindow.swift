import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let model: SettingsModel

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        modelManager: ModelManager = ModelManager(),
        dictionaryEngine: DictionaryEngine = DictionaryEngine(),
        learningStore: LearningStore? = nil,
        onSettingsChanged: @escaping (AppSettings) -> Void = { _ in },
        onModelMetadataChanged: @escaping () -> Void = {},
        modelPreparationAction: @escaping (ModelTier) async throws -> Void = { _ in },
        onShowAppModes: @escaping () -> Void = {},
        onShowPrivacy: @escaping () -> Void = {},
        onLearningChanged: @escaping (MemorySnapshot) -> Void = { _ in }
    ) {
        model = SettingsModel(
            settingsStore: settingsStore,
            modelManager: modelManager,
            dictionaryEngine: dictionaryEngine,
            learningStore: learningStore,
            onSettingsChanged: onSettingsChanged,
            onModelMetadataChanged: onModelMetadataChanged,
            modelPreparationAction: modelPreparationAction,
            onShowAppModes: onShowAppModes,
            onShowPrivacy: onShowPrivacy,
            onLearningChanged: onLearningChanged
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 700),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Flint Settings"
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        model.refresh()
        Task { await model.refreshVocabulary() }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        model.refresh()
    }
}

struct VocabularyApplicationOption: Identifiable, Hashable {
    let name: String
    let bundleIdentifier: String

    var id: String { bundleIdentifier }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var modelMetadata: [ModelMetadata] = []
    @Published private(set) var customReplacements: [LearningMemory] = []
    @Published var newHeardPhrase = ""
    @Published var newPreferredReplacement = ""
    @Published var newVocabularyLanguage = "auto"
    @Published var newVocabularyScope: LearningScopeKind = .global
    @Published var newVocabularyApplicationBundleID = ""
    @Published private(set) var vocabularyApplications: [VocabularyApplicationOption] = []
    @Published var pendingVocabularyConflict: LearningMemory?
    @Published private(set) var statusMessage = ""
    @Published private(set) var errorMessage = ""
    @Published private(set) var activeModelOperationTier: ModelTier?

    private let settingsStore: AppSettingsStore
    private let modelManager: ModelManager
    private let dictionaryEngine: DictionaryEngine
    private let learningStore: LearningStore?
    private let onSettingsChanged: (AppSettings) -> Void
    private let onModelMetadataChanged: () -> Void
    private let modelPreparationAction: (ModelTier) async throws -> Void
    private let onShowAppModes: () -> Void
    private let onShowPrivacy: () -> Void
    private let onLearningChanged: (MemorySnapshot) -> Void
    private let runningApplicationsProvider: @MainActor () -> [VocabularyApplicationOption]

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        modelManager: ModelManager = ModelManager(),
        dictionaryEngine: DictionaryEngine = DictionaryEngine(),
        learningStore: LearningStore? = nil,
        onSettingsChanged: @escaping (AppSettings) -> Void = { _ in },
        onModelMetadataChanged: @escaping () -> Void = {},
        modelPreparationAction: @escaping (ModelTier) async throws -> Void = { _ in },
        onShowAppModes: @escaping () -> Void = {},
        onShowPrivacy: @escaping () -> Void = {},
        onLearningChanged: @escaping (MemorySnapshot) -> Void = { _ in },
        runningApplicationsProvider: @escaping @MainActor () -> [VocabularyApplicationOption] = SettingsModel.runningApplications
    ) {
        self.settingsStore = settingsStore
        self.modelManager = modelManager
        self.dictionaryEngine = dictionaryEngine
        self.learningStore = learningStore
        self.onSettingsChanged = onSettingsChanged
        self.onModelMetadataChanged = onModelMetadataChanged
        self.modelPreparationAction = modelPreparationAction
        self.onShowAppModes = onShowAppModes
        self.onShowPrivacy = onShowPrivacy
        self.onLearningChanged = onLearningChanged
        self.runningApplicationsProvider = runningApplicationsProvider
        settings = settingsStore.load()
        newVocabularyLanguage = settings.language
        refresh()
    }

    func refresh() {
        settings = settingsStore.load()
        modelMetadata = modelManager.metadata()
        vocabularyApplications = runningApplicationsProvider()
        if learningStore == nil {
            customReplacements = dictionaryEngine.listCustomReplacements().map(Self.legacyMemory)
        }
    }

    func setShortcutOption(_ option: ShortcutOption) {
        var shortcutSettings = settingsStore.load().shortcutSettings
        shortcutSettings.option = option
        settingsStore.saveShortcutSettings(shortcutSettings)
        publishSettingsChange("Shortcut saved.")
    }

    func setShortcutInputBehavior(_ behavior: ShortcutInputBehavior) {
        var shortcutSettings = settingsStore.load().shortcutSettings
        shortcutSettings.behavior = behavior
        settingsStore.saveShortcutSettings(shortcutSettings)
        publishSettingsChange("Shortcut behavior saved.")
    }

    func setCleanupMode(_ mode: CleanupMode) {
        settingsStore.saveCleanupMode(mode)
        publishSettingsChange("Default cleanup mode saved.")
    }

    func setRemoveFillerWords(_ enabled: Bool) {
        settingsStore.saveRemoveFillerWords(enabled)
        publishSettingsChange(enabled ? "Filler-word removal enabled." : "Filler-word removal disabled.")
    }

    func setAddTerminalPunctuation(_ enabled: Bool) {
        settingsStore.saveAddTerminalPunctuation(enabled)
        publishSettingsChange(enabled ? "Terminal punctuation enabled." : "Terminal punctuation disabled.")
    }

    func setInsertionTargetBehavior(_ behavior: InsertionTargetBehavior) {
        settingsStore.saveInsertionTargetBehavior(behavior)
        publishSettingsChange("Insertion target saved.")
    }

    func setAppAwareModesEnabled(_ enabled: Bool) {
        settingsStore.saveAppAwareModesEnabled(enabled)
        publishSettingsChange(enabled ? "App-aware modes enabled." : "App-aware modes disabled.")
    }

    func showAppModes() {
        onShowAppModes()
    }

    func setSelectedModelTier(_ tier: ModelTier) {
        settingsStore.saveSelectedModelTier(tier)
        publishSettingsChange("\(tier.displayName) selected.")
        refreshModelMetadata()
    }

    func downloadSelectedModel() async {
        let tier = settings.selectedModelTier
        activeModelOperationTier = tier
        statusMessage = "Downloading \(tier.displayName)..."
        errorMessage = ""
        do {
            _ = try await modelManager.downloadModel(for: tier)
            statusMessage = "Preparing \(tier.displayName)..."
            try await modelPreparationAction(tier)
            refreshModelMetadata()
            onModelMetadataChanged()
            statusMessage = "\(tier.displayName) model is ready."
        } catch {
            refreshModelMetadata()
            statusMessage = ""
            errorMessage = error.localizedDescription
        }
        activeModelOperationTier = nil
    }

    func deleteSelectedModel() {
        let tier = settings.selectedModelTier
        activeModelOperationTier = tier
        errorMessage = ""
        do {
            try modelManager.deleteModel(for: tier)
            refreshModelMetadata()
            onModelMetadataChanged()
            statusMessage = "\(tier.displayName) model deleted."
        } catch {
            refreshModelMetadata()
            statusMessage = ""
            errorMessage = error.localizedDescription
        }
        activeModelOperationTier = nil
    }

    func addVocabularyReplacement(replaceExisting: Bool = false) async {
        let heardPhrase = newHeardPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredReplacement = newPreferredReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heardPhrase.isEmpty, !preferredReplacement.isEmpty else {
            statusMessage = ""
            errorMessage = "Enter both phrases before adding a vocabulary item."
            return
        }
        guard heardPhrase != preferredReplacement else {
            statusMessage = ""
            errorMessage = "Heard and preferred forms must be different."
            return
        }
        let scopeValue = newVocabularyScope == .global
            ? ""
            : newVocabularyApplicationBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard newVocabularyScope != .application || !scopeValue.isEmpty else {
            statusMessage = ""
            errorMessage = "Choose an application for an app-specific vocabulary item."
            return
        }

        if let learningStore {
            do {
                let language = newVocabularyLanguage.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedLanguage = language.isEmpty ? "auto" : language
                let existing = try await learningStore.listMemories().first { memory in
                    memory.scopeKind == newVocabularyScope
                        && memory.scopeValue == scopeValue
                        && memory.language == normalizedLanguage
                        && memory.heardKey == VocabularyNormalizer.key(for: heardPhrase)
                }
                if let existing,
                   existing.preferredForm != preferredReplacement,
                   !replaceExisting {
                    pendingVocabularyConflict = existing
                    statusMessage = ""
                    errorMessage = "A mapping for this phrase already exists in the selected scope."
                    return
                }

                _ = try await learningStore.upsertMemory(LearningMemoryDraft(
                    heardForm: heardPhrase,
                    preferredForm: preferredReplacement,
                    scopeKind: newVocabularyScope,
                    scopeValue: scopeValue,
                    language: normalizedLanguage,
                    status: .active,
                    origin: .seeded
                ))
                let snapshot = try await learningStore.memorySnapshot()
                onLearningChanged(snapshot)
                await refreshVocabulary()
                pendingVocabularyConflict = nil
            } catch {
                statusMessage = ""
                errorMessage = error.localizedDescription
                return
            }
        } else {
            _ = dictionaryEngine.addReplacement(
                heardPhrase: heardPhrase,
                preferredReplacement: preferredReplacement
            )
            customReplacements = dictionaryEngine.listCustomReplacements().map(Self.legacyMemory)
        }

        newHeardPhrase = ""
        newPreferredReplacement = ""
        statusMessage = replaceExisting ? "Vocabulary item replaced." : "Vocabulary item added."
        errorMessage = ""
    }

    func deleteVocabularyReplacement(_ replacement: LearningMemory) async {
        if let learningStore {
            do {
                try await learningStore.deleteMemory(id: replacement.id)
                let snapshot = try await learningStore.memorySnapshot()
                onLearningChanged(snapshot)
                await refreshVocabulary()
            } catch {
                statusMessage = ""
                errorMessage = error.localizedDescription
                return
            }
        } else {
            dictionaryEngine.removeReplacement(id: replacement.id)
            customReplacements = dictionaryEngine.listCustomReplacements().map(Self.legacyMemory)
        }
        statusMessage = "Vocabulary item deleted."
        errorMessage = ""
    }

    func setStoreHistory(_ enabled: Bool) {
        settingsStore.saveStoreHistory(enabled)
        publishSettingsChange(enabled ? "History storage enabled." : "History storage disabled.")
    }

    func setPlayStartSound(_ enabled: Bool) {
        settingsStore.savePlayStartSound(enabled)
        publishSettingsChange(enabled ? "Start sound enabled." : "Start sound disabled.")
    }

    func setPlayStopSound(_ enabled: Bool) {
        settingsStore.savePlayStopSound(enabled)
        publishSettingsChange(enabled ? "Stop sound enabled." : "Stop sound disabled.")
    }

    func showPrivacy() {
        onShowPrivacy()
    }

    func metadata(for tier: ModelTier) -> ModelMetadata? {
        modelMetadata.first { $0.tier == tier }
    }

    private func publishSettingsChange(_ message: String) {
        settings = settingsStore.load()
        onSettingsChanged(settings)
        statusMessage = message
        errorMessage = ""
    }

    private func refreshModelMetadata() {
        modelMetadata = modelManager.metadata()
    }

    func refreshVocabulary() async {
        guard let learningStore else { return }
        do {
            customReplacements = try await learningStore.listMemories()
            errorMessage = ""
        } catch {
            customReplacements = []
            errorMessage = error.localizedDescription
        }
    }

    private static func legacyMemory(_ replacement: DictionaryReplacement) -> LearningMemory {
        LearningMemory(
            id: replacement.id,
            memoryType: .vocabulary,
            scopeKind: .global,
            scopeValue: "",
            language: "auto",
            heardForm: replacement.heardPhrase,
            heardKey: VocabularyNormalizer.key(for: replacement.heardPhrase),
            preferredForm: replacement.preferredReplacement,
            confidence: 1,
            evidenceCount: 1,
            usageCount: replacement.usageCount,
            status: .active,
            origin: .seeded,
            createdAt: replacement.createdAt,
            updatedAt: replacement.updatedAt,
            lastUsedAt: nil
        )
    }

    private static func runningApplications() -> [VocabularyApplicationOption] {
        var seen: Set<String> = []
        return NSWorkspace.shared.runningApplications
            .compactMap { application -> VocabularyApplicationOption? in
                guard let bundleIdentifier = application.bundleIdentifier,
                      !bundleIdentifier.isEmpty,
                      seen.insert(bundleIdentifier).inserted else { return nil }
                return VocabularyApplicationOption(
                    name: application.localizedName ?? bundleIdentifier,
                    bundleIdentifier: bundleIdentifier
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct SettingsView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Only controls backed by current Flint behavior are shown.")
                        .foregroundStyle(.secondary)
                }

                SettingsSection("Dictation") {
                    SettingsPickerRow(
                        title: "Shortcut",
                        detail: "Choose the key combination Flint listens for.",
                        width: 190,
                        selection: Binding(
                            get: { model.settings.shortcutSettings.option },
                            set: { model.setShortcutOption($0) }
                        )
                    ) {
                        ForEach(ShortcutOption.allCases, id: \.self) { option in
                            Text(option.displayName).tag(option)
                        }
                    }

                    SettingsPickerRow(
                        title: "Shortcut Behavior",
                        detail: "Hold to record, or press once to start and again to stop.",
                        width: 190,
                        selection: Binding(
                            get: { model.settings.shortcutSettings.behavior },
                            set: { model.setShortcutInputBehavior($0) }
                        )
                    ) {
                        ForEach(ShortcutInputBehavior.allCases, id: \.self) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }

                    SettingsPickerRow(
                        title: "Default Cleanup",
                        detail: "Used unless an enabled app mode overrides it.",
                        width: 190,
                        selection: Binding(
                            get: { model.settings.cleanupMode },
                            set: { model.setCleanupMode($0) }
                        )
                    ) {
                        ForEach(CleanupMode.allCases, id: \.self) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }

                    SettingsPickerRow(
                        title: "Insertion Target",
                        detail: "Insert into the original field or whichever field is focused when transcription finishes.",
                        width: 190,
                        selection: Binding(
                            get: { model.settings.insertionTargetBehavior },
                            set: { model.setInsertionTargetBehavior($0) }
                        )
                    ) {
                        ForEach(InsertionTargetBehavior.allCases, id: \.self) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                }

                SettingsSection("App Modes") {
                    HStack(alignment: .center, spacing: 12) {
                        Toggle("Enable app-aware modes", isOn: Binding(
                            get: { model.settings.appAwareModesEnabled },
                            set: { model.setAppAwareModesEnabled($0) }
                        ))
                        .toggleStyle(.checkbox)
                        Spacer()
                        Button("Configure App Modes") {
                            model.showAppModes()
                        }
                    }
                    .padding(12)
                    .settingsRowBorder()
                }

                SettingsSection("Feedback") {
                    Toggle("Play sound when recording starts", isOn: Binding(
                        get: { model.settings.playStartSound },
                        set: { model.setPlayStartSound($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .padding(12)
                    .settingsRowBorder()

                    Toggle("Play sound when recording stops", isOn: Binding(
                        get: { model.settings.playStopSound },
                        set: { model.setPlayStopSound($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .padding(12)
                    .settingsRowBorder()
                }

                SettingsSection("Formatting") {
                    Toggle("Remove filler words", isOn: Binding(
                        get: { model.settings.removeFillerWords },
                        set: { model.setRemoveFillerWords($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .padding(12)
                    .settingsRowBorder()

                    Toggle("Add terminal punctuation", isOn: Binding(
                        get: { model.settings.addTerminalPunctuation },
                        set: { model.setAddTerminalPunctuation($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .padding(12)
                    .settingsRowBorder()
                }

                SettingsSection("Models") {
                    SettingsPickerRow(
                        title: "Selected Model",
                        detail: "The selected tier is used for transcription.",
                        width: 190,
                        selection: Binding(
                            get: { model.settings.selectedModelTier },
                            set: { model.setSelectedModelTier($0) }
                        )
                    ) {
                        ForEach(ModelTier.allCases, id: \.self) { tier in
                            Text(tier.displayName).tag(tier)
                        }
                    }

                    ForEach(model.modelMetadata, id: \.tier) { metadata in
                        ModelSettingsRow(
                            metadata: metadata,
                            isSelected: metadata.tier == model.settings.selectedModelTier,
                            isBusy: model.activeModelOperationTier == metadata.tier,
                            onSelect: { model.setSelectedModelTier(metadata.tier) },
                            onDownload: {
                                Task { await model.downloadSelectedModel() }
                            },
                            onDelete: { model.deleteSelectedModel() }
                        )
                    }
                }

                SettingsSection("Custom Vocabulary") {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("Flint hears", text: $model.newHeardPhrase)
                                .textFieldStyle(.roundedBorder)
                            TextField("Flint should write", text: $model.newPreferredReplacement)
                                .textFieldStyle(.roundedBorder)
                        }

                        HStack(spacing: 8) {
                            Picker("Scope", selection: $model.newVocabularyScope) {
                                Text("Global").tag(LearningScopeKind.global)
                                Text("Application").tag(LearningScopeKind.application)
                            }
                            .frame(width: 180)

                            if model.newVocabularyScope == .application {
                                Picker("Application", selection: $model.newVocabularyApplicationBundleID) {
                                    Text("Choose an app").tag("")
                                    ForEach(model.vocabularyApplications) { application in
                                        Text(application.name).tag(application.bundleIdentifier)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            }

                            TextField("Language (auto)", text: $model.newVocabularyLanguage)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 140)

                            Button("Teach Flint") {
                                Task { await model.addVocabularyReplacement() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    if model.customReplacements.isEmpty {
                        Text("No custom vocabulary entries.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(model.customReplacements) { replacement in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(replacement.heardForm)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(replacement.preferredForm)
                                            .foregroundStyle(.secondary)
                                        Text(replacement.scopeKind == .global ? "Global" : replacement.scopeValue)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.tertiary)
                                    }
                                    Spacer()
                                    Button("Delete", role: .destructive) {
                                        Task { await model.deleteVocabularyReplacement(replacement) }
                                    }
                                }
                                .padding(12)
                                .settingsRowBorder()
                            }
                        }
                    }
                }

                SettingsSection("Privacy") {
                    HStack(spacing: 12) {
                        Toggle("Store dictation history", isOn: Binding(
                            get: { model.settings.storeHistory },
                            set: { model.setStoreHistory($0) }
                        ))
                        .toggleStyle(.checkbox)
                        Spacer()
                        Button("Open Privacy") {
                            model.showPrivacy()
                        }
                    }
                    .padding(12)
                    .settingsRowBorder()
                }

                if !model.statusMessage.isEmpty {
                    Text(model.statusMessage)
                        .foregroundStyle(.secondary)
                }
                if !model.errorMessage.isEmpty {
                    Text(model.errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 760, minHeight: 700)
        .alert(
            "Replace existing mapping?",
            isPresented: Binding(
                get: { model.pendingVocabularyConflict != nil },
                set: { if !$0 { model.pendingVocabularyConflict = nil } }
            )
        ) {
            Button("Replace") {
                Task { await model.addVocabularyReplacement(replaceExisting: true) }
            }
            Button("Cancel", role: .cancel) {
                model.pendingVocabularyConflict = nil
            }
        } message: {
            if let conflict = model.pendingVocabularyConflict {
                Text("“\(conflict.heardForm)” currently becomes “\(conflict.preferredForm)” in this scope.")
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    private let title: String
    private let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            VStack(spacing: 8) {
                content
            }
        }
    }
}

private struct SettingsPickerRow<SelectionValue: Hashable, Content: View>: View {
    let title: String
    let detail: String
    let width: CGFloat
    @Binding var selection: SelectionValue
    let content: Content

    init(
        title: String,
        detail: String,
        width: CGFloat,
        selection: Binding<SelectionValue>,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.width = width
        _selection = selection
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 16)
            Picker(title, selection: $selection) {
                content
            }
            .labelsHidden()
            .frame(width: width)
        }
        .padding(12)
        .settingsRowBorder()
    }
}

private struct ModelSettingsRow: View {
    let metadata: ModelMetadata
    let isSelected: Bool
    let isBusy: Bool
    let onSelect: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(metadata.displayName)
                        .font(.system(size: 13, weight: .semibold))
                    if isSelected {
                        Text("Selected")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("\(metadata.modelName) · \(metadata.sizeLabel) · \(metadata.hardwareLabel)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text(metadata.isInstalled ? "Installed" : "Not installed")
                    .font(.system(size: 12))
                    .foregroundStyle(metadata.isInstalled ? Color.secondary : Color.red)
            }
            Spacer(minLength: 16)
            if !isSelected {
                Button("Select", action: onSelect)
                    .disabled(isBusy)
            }
            Button(metadata.isInstalled ? "Installed" : "Download", action: onDownload)
                .disabled(!isSelected || metadata.isInstalled || isBusy)
            Button("Delete", role: .destructive, action: onDelete)
                .disabled(!isSelected || !metadata.isInstalled || isBusy)
        }
        .padding(12)
        .settingsRowBorder()
    }
}

private extension View {
    func settingsRowBorder() -> some View {
        overlay(
            Rectangle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
