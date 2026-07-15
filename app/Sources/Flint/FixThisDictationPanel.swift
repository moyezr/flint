import AppKit
import SwiftUI

enum FixThisDictationPresentation {
    case full
    case quick
}

@MainActor
final class FixThisDictationWindowController {
    private let window: NSWindow
    let model: FixThisDictationModel

    init(
        entries: [RecentDictation],
        learningStore: LearningStore,
        onLearningChanged: @escaping (MemorySnapshot) -> Void,
        onSaved: @escaping (Bool) -> Void = { _ in },
        onCancel: @escaping () -> Void = {},
        onProposalShown: @escaping () -> Void = {},
        onDismiss: @escaping () -> Void = {},
        presentation: FixThisDictationPresentation = .full
    ) {
        model = FixThisDictationModel(
            entries: entries,
            learningStore: learningStore,
            onLearningChanged: onLearningChanged,
            onSaved: onSaved,
            onCancel: onCancel,
            onProposalShown: onProposalShown
        )
        let windowSize = presentation == .quick
            ? NSSize(width: 590, height: 500)
            : NSSize(width: 720, height: 640)
        window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = presentation == .quick ? "Correct Last Dictation" : "Fix This Dictation"
        window.contentView = NSHostingView(rootView: FixThisDictationView(model: model, presentation: presentation))
        window.isReleasedWhenClosed = false
        window.center()

        model.onDismiss = { [weak window] in
            window?.orderOut(nil)
            onDismiss()
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func update(entries: [RecentDictation]) {
        model.update(entries: entries)
    }
}

@MainActor
final class FixThisDictationModel: ObservableObject {
    typealias SaveAction = (ExplicitCorrectionWrite) async throws -> ExplicitCorrectionWriteResult
    typealias SnapshotAction = () async throws -> MemorySnapshot

    @Published private(set) var entries: [RecentDictation]
    @Published var selectedID: UUID? {
        didSet {
            guard selectedID != oldValue else { return }
            loadSelectedEntry()
        }
    }
    @Published private(set) var originalText = ""
    @Published var correctedText = "" {
        didSet {
            guard correctedText != oldValue else { return }
            updateProposal()
        }
    }
    @Published var scopeKind: LearningScopeKind = .global
    @Published var includeMapping = true
    @Published private(set) var proposal: CorrectionProposal?
    @Published private(set) var mappingSafety: CorrectionMappingSafety = .direct
    @Published private(set) var isSaving = false
    @Published private(set) var statusMessage = ""
    @Published private(set) var errorMessage = ""

    var onDismiss: () -> Void = {}

    private let extractor: CorrectionDiffExtractor
    private let mappingPolicy: CorrectionMappingPolicy
    private let saveAction: SaveAction
    private let snapshotAction: SnapshotAction
    private let copyAction: @MainActor (String) -> Void
    private let onLearningChanged: (MemorySnapshot) -> Void
    private let onSaved: (Bool) -> Void
    private let onCancel: () -> Void
    private let onProposalShown: () -> Void
    private var entriesWithShownProposal: Set<UUID> = []

    init(
        entries: [RecentDictation],
        learningStore: LearningStore,
        extractor: CorrectionDiffExtractor = CorrectionDiffExtractor(),
        mappingPolicy: CorrectionMappingPolicy = CorrectionMappingPolicy(),
        copyAction: @escaping @MainActor (String) -> Void = FixThisDictationModel.copyToClipboard,
        onLearningChanged: @escaping (MemorySnapshot) -> Void = { _ in },
        onSaved: @escaping (Bool) -> Void = { _ in },
        onCancel: @escaping () -> Void = {},
        onProposalShown: @escaping () -> Void = {}
    ) {
        self.entries = entries
        selectedID = entries.first?.id
        self.extractor = extractor
        self.mappingPolicy = mappingPolicy
        saveAction = { write in try await learningStore.saveExplicitCorrection(write) }
        snapshotAction = { try await learningStore.memorySnapshot() }
        self.copyAction = copyAction
        self.onLearningChanged = onLearningChanged
        self.onSaved = onSaved
        self.onCancel = onCancel
        self.onProposalShown = onProposalShown
        loadSelectedEntry()
    }

    init(
        entries: [RecentDictation],
        extractor: CorrectionDiffExtractor = CorrectionDiffExtractor(),
        mappingPolicy: CorrectionMappingPolicy = CorrectionMappingPolicy(),
        saveAction: @escaping SaveAction,
        snapshotAction: @escaping SnapshotAction = { .empty },
        copyAction: @escaping @MainActor (String) -> Void = { _ in },
        onLearningChanged: @escaping (MemorySnapshot) -> Void = { _ in },
        onSaved: @escaping (Bool) -> Void = { _ in },
        onCancel: @escaping () -> Void = {},
        onProposalShown: @escaping () -> Void = {}
    ) {
        self.entries = entries
        selectedID = entries.first?.id
        self.extractor = extractor
        self.mappingPolicy = mappingPolicy
        self.saveAction = saveAction
        self.snapshotAction = snapshotAction
        self.copyAction = copyAction
        self.onLearningChanged = onLearningChanged
        self.onSaved = onSaved
        self.onCancel = onCancel
        self.onProposalShown = onProposalShown
        loadSelectedEntry()
    }

    var selectedEntry: RecentDictation? {
        entries.first { $0.id == selectedID }
    }

    var canSave: Bool {
        !isSaving
            && !correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && correctedText != originalText
            && selectedEntry != nil
    }

    var canUseApplicationScope: Bool {
        guard let bundleID = selectedEntry?.applicationBundleID else { return false }
        return !bundleID.isEmpty
    }

    var proposalScopeDescription: String {
        guard scopeKind == .application, let entry = selectedEntry else { return "globally" }
        return "in \(entry.applicationName ?? entry.applicationBundleID ?? "this app")"
    }

    func update(entries: [RecentDictation]) {
        self.entries = entries
        if !entries.contains(where: { $0.id == selectedID }) {
            selectedID = entries.first?.id
        }
    }

    func saveAndCopy() async {
        guard canSave, let entry = selectedEntry else { return }
        isSaving = true
        statusMessage = ""
        errorMessage = ""
        defer { isSaving = false }

        let memoryDraft: LearningMemoryDraft?
        if includeMapping, mappingSafety == .direct, let proposal {
            let effectiveScope: LearningScopeKind = scopeKind == .application && canUseApplicationScope
                ? .application
                : .global
            memoryDraft = LearningMemoryDraft(
                heardForm: proposal.heardForm,
                preferredForm: proposal.preferredForm,
                scopeKind: effectiveScope,
                scopeValue: effectiveScope == .application ? entry.applicationBundleID ?? "" : "",
                language: entry.language,
                status: .active,
                origin: .explicitCorrection
            )
        } else {
            memoryDraft = nil
        }

        let write = ExplicitCorrectionWrite(
            memory: memoryDraft,
            evidence: CorrectionEvidenceDraft(
                originalText: entry.insertedText,
                correctedText: correctedText,
                applicationBundleID: entry.applicationBundleID ?? "",
                language: entry.language,
                cleanupMode: entry.cleanupMode,
                source: .explicitFix,
                createdAt: Date()
            )
        )

        do {
            let result = try await saveAction(write)
            if result.memory != nil {
                onLearningChanged(try await snapshotAction())
            }
            copyAction(correctedText)
            onSaved(result.memory != nil)
            statusMessage = "Correction saved and copied."
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() {
        onCancel()
        onDismiss()
    }

    private func loadSelectedEntry() {
        guard let entry = selectedEntry else {
            originalText = ""
            correctedText = ""
            proposal = nil
            mappingSafety = .direct
            scopeKind = .global
            return
        }
        originalText = entry.insertedText
        correctedText = entry.insertedText
        scopeKind = entry.applicationBundleID?.isEmpty == false ? .application : .global
        statusMessage = ""
        errorMessage = ""
        updateProposal()
    }

    private func updateProposal() {
        guard !correctedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            proposal = nil
            includeMapping = false
            return
        }
        proposal = extractor.extract(original: originalText, corrected: correctedText)
        mappingSafety = proposal.map(mappingPolicy.safety) ?? .direct
        includeMapping = proposal != nil && mappingSafety == .direct
        if proposal != nil,
           mappingSafety == .direct,
           let selectedID,
           entriesWithShownProposal.insert(selectedID).inserted {
            onProposalShown()
        }
    }

    private static func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct FixThisDictationView: View {
    @ObservedObject var model: FixThisDictationModel
    let presentation: FixThisDictationPresentation
    @FocusState private var isCorrectionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(presentation == .quick ? "Correct Last Dictation" : "Fix This Dictation")
                    .font(.system(size: 26, weight: .semibold))
                Text(presentation == .quick
                    ? "Edit what Flint wrote. A reusable correction is suggested only when the change is safe and specific."
                    : "Choose a frozen recent output, correct it, then explicitly decide whether Flint should reuse the change.")
                    .foregroundStyle(.secondary)
            }

            if presentation == .full || model.entries.count > 1 {
                Picker("Recent dictation", selection: $model.selectedID) {
                    ForEach(model.entries) { entry in
                        Text(Self.label(for: entry)).tag(Optional(entry.id))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Flint wrote")
                    .font(.headline)
                ScrollView {
                    Text(model.originalText)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                }
                .frame(
                    minHeight: presentation == .quick ? 58 : 90,
                    maxHeight: presentation == .quick ? 82 : 130
                )
                .overlay(Rectangle().stroke(Color(nsColor: .separatorColor)))
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("You meant")
                    .font(.headline)
                TextEditor(text: $model.correctedText)
                    .font(.body)
                    .frame(minHeight: presentation == .quick ? 88 : 110)
                    .padding(6)
                    .overlay(Rectangle().stroke(Color(nsColor: .separatorColor)))
                    .focused($isCorrectionFocused)
            }

            if let proposal = model.proposal, model.mappingSafety == .direct {
                VStack(alignment: .leading, spacing: 10) {
                    Toggle(isOn: $model.includeMapping) {
                        Text("Learn “\(proposal.heardForm)” → “\(proposal.preferredForm)” \(model.proposalScopeDescription)")
                    }
                    .toggleStyle(.checkbox)

                    Picker("Use this mapping", selection: $model.scopeKind) {
                        Text("Only this application").tag(LearningScopeKind.application)
                            .disabled(!model.canUseApplicationScope)
                        Text("Everywhere").tag(LearningScopeKind.global)
                    }
                    .frame(width: 260)
                    .disabled(!model.includeMapping)
                }
                .padding(12)
                .background(Color.orange.opacity(0.08))
                .overlay(Rectangle().stroke(Color.orange.opacity(0.35)))
            } else if model.proposal != nil, model.mappingSafety == .contextRequired {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.shield.fill")
                        .foregroundStyle(.orange)
                    Text("This phrase has another common meaning, so Flint will save the correction as evidence without creating a blind replacement. In Teach Flint, use a distinctive spoken form such as “next jay ess” instead.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color.orange.opacity(0.08))
                .overlay(Rectangle().stroke(Color.orange.opacity(0.35)))
            } else if model.correctedText != model.originalText {
                Text("This correction will be saved as evidence only; it does not contain one bounded reusable substitution.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            if !model.errorMessage.isEmpty {
                Text(model.errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                Text("Save & Copy never rewrites the original field.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button(model.isSaving ? "Saving…" : "Save & Copy") {
                    Task { await model.saveAndCopy() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(
            minWidth: presentation == .quick ? 590 : 720,
            minHeight: presentation == .quick ? 500 : 640
        )
        .onAppear {
            if presentation == .quick {
                DispatchQueue.main.async { isCorrectionFocused = true }
            }
        }
    }

    private static func label(for entry: RecentDictation) -> String {
        let app = entry.applicationName ?? "Unknown app"
        let preview = entry.insertedText.replacingOccurrences(of: "\n", with: " ").prefix(54)
        return "\(app) · \(RelativeAgeFormatter.string(from: entry.createdAt)) · \(preview)"
    }
}

private enum RelativeAgeFormatter {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.localizedString(for: date, relativeTo: Date())
    }
}
