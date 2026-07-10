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
        onSettingsChanged: @escaping (AppSettings) -> Void = { _ in },
        onModelMetadataChanged: @escaping () -> Void = {},
        modelPreparationAction: @escaping (ModelTier) async throws -> Void = { _ in },
        onShowAppModes: @escaping () -> Void = {},
        onShowPrivacy: @escaping () -> Void = {}
    ) {
        model = SettingsModel(
            settingsStore: settingsStore,
            modelManager: modelManager,
            dictionaryEngine: dictionaryEngine,
            onSettingsChanged: onSettingsChanged,
            onModelMetadataChanged: onModelMetadataChanged,
            modelPreparationAction: modelPreparationAction,
            onShowAppModes: onShowAppModes,
            onShowPrivacy: onShowPrivacy
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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func refresh() {
        model.refresh()
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var modelMetadata: [ModelMetadata] = []
    @Published private(set) var customReplacements: [DictionaryReplacement] = []
    @Published var newHeardPhrase = ""
    @Published var newPreferredReplacement = ""
    @Published private(set) var statusMessage = ""
    @Published private(set) var errorMessage = ""
    @Published private(set) var activeModelOperationTier: ModelTier?

    private let settingsStore: AppSettingsStore
    private let modelManager: ModelManager
    private let dictionaryEngine: DictionaryEngine
    private let onSettingsChanged: (AppSettings) -> Void
    private let onModelMetadataChanged: () -> Void
    private let modelPreparationAction: (ModelTier) async throws -> Void
    private let onShowAppModes: () -> Void
    private let onShowPrivacy: () -> Void

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        modelManager: ModelManager = ModelManager(),
        dictionaryEngine: DictionaryEngine = DictionaryEngine(),
        onSettingsChanged: @escaping (AppSettings) -> Void = { _ in },
        onModelMetadataChanged: @escaping () -> Void = {},
        modelPreparationAction: @escaping (ModelTier) async throws -> Void = { _ in },
        onShowAppModes: @escaping () -> Void = {},
        onShowPrivacy: @escaping () -> Void = {}
    ) {
        self.settingsStore = settingsStore
        self.modelManager = modelManager
        self.dictionaryEngine = dictionaryEngine
        self.onSettingsChanged = onSettingsChanged
        self.onModelMetadataChanged = onModelMetadataChanged
        self.modelPreparationAction = modelPreparationAction
        self.onShowAppModes = onShowAppModes
        self.onShowPrivacy = onShowPrivacy
        settings = settingsStore.load()
        refresh()
    }

    func refresh() {
        settings = settingsStore.load()
        modelMetadata = modelManager.metadata()
        customReplacements = dictionaryEngine.listCustomReplacements()
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

    func addVocabularyReplacement() {
        let heardPhrase = newHeardPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferredReplacement = newPreferredReplacement.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heardPhrase.isEmpty, !preferredReplacement.isEmpty else {
            statusMessage = ""
            errorMessage = "Enter both phrases before adding a vocabulary item."
            return
        }

        _ = dictionaryEngine.addReplacement(
            heardPhrase: heardPhrase,
            preferredReplacement: preferredReplacement
        )
        newHeardPhrase = ""
        newPreferredReplacement = ""
        refreshVocabulary()
        statusMessage = "Vocabulary item added."
        errorMessage = ""
    }

    func deleteVocabularyReplacement(_ replacement: DictionaryReplacement) {
        dictionaryEngine.removeReplacement(id: replacement.id)
        refreshVocabulary()
        statusMessage = "Vocabulary item deleted."
        errorMessage = ""
    }

    func setStoreHistory(_ enabled: Bool) {
        settingsStore.saveStoreHistory(enabled)
        publishSettingsChange(enabled ? "History storage enabled." : "History storage disabled.")
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

    private func refreshVocabulary() {
        customReplacements = dictionaryEngine.listCustomReplacements()
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
                    HStack(spacing: 8) {
                        TextField("Heard phrase", text: $model.newHeardPhrase)
                            .textFieldStyle(.roundedBorder)
                        TextField("Replacement", text: $model.newPreferredReplacement)
                            .textFieldStyle(.roundedBorder)
                        Button("Add") {
                            model.addVocabularyReplacement()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if model.customReplacements.isEmpty {
                        Text("No custom vocabulary entries.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(model.customReplacements) { replacement in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(replacement.heardPhrase)
                                            .font(.system(size: 13, weight: .semibold))
                                        Text(replacement.preferredReplacement)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Delete", role: .destructive) {
                                        model.deleteVocabularyReplacement(replacement)
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
