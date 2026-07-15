import AppKit
import SwiftUI

@MainActor
final class QuickVocabularyWindowController {
    private let window: NSWindow
    private let dismissObserver: QuickVocabularyWindowDismissObserver
    let model: QuickVocabularyModel

    init(
        recentDictation: RecentDictation?,
        learningStore: LearningStore,
        learningMetrics: LearningMetrics,
        onLearningChanged: @escaping (MemorySnapshot) -> Void,
        onDismiss: @escaping () -> Void = {}
    ) {
        model = QuickVocabularyModel(
            recentDictation: recentDictation,
            learningStore: learningStore,
            learningMetrics: learningMetrics,
            onLearningChanged: onLearningChanged
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 330),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Teach Flint"
        window.contentView = NSHostingView(rootView: QuickVocabularyView(model: model))
        window.isReleasedWhenClosed = false
        window.center()

        let dismissObserver = QuickVocabularyWindowDismissObserver(onDismiss: onDismiss)
        self.dismissObserver = dismissObserver
        window.delegate = dismissObserver
        model.onDismiss = { [weak window, weak dismissObserver] in
            guard let window else { return }
            window.orderOut(nil)
            dismissObserver?.notifyDismissed()
        }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private final class QuickVocabularyWindowDismissObserver: NSObject, NSWindowDelegate {
    private let onDismiss: () -> Void
    private var didNotify = false

    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }

    func windowWillClose(_ notification: Notification) {
        notifyDismissed()
    }

    func notifyDismissed() {
        guard !didNotify else { return }
        didNotify = true
        onDismiss()
    }
}

@MainActor
final class QuickVocabularyModel: ObservableObject {
    typealias SaveAction = (LearningMemoryDraft) async throws -> MemorySnapshot

    @Published var heardPhrase = ""
    @Published var preferredPhrase = ""
    @Published var scopeKind: LearningScopeKind
    @Published private(set) var isSaving = false
    @Published private(set) var errorMessage = ""

    let recentDictation: RecentDictation?
    var onDismiss: () -> Void = {}

    private let saveAction: SaveAction
    private let onLearningChanged: (MemorySnapshot) -> Void
    private let onSaved: () -> Void
    private let mappingPolicy = CorrectionMappingPolicy()

    init(
        recentDictation: RecentDictation?,
        learningStore: LearningStore,
        learningMetrics: LearningMetrics,
        onLearningChanged: @escaping (MemorySnapshot) -> Void
    ) {
        self.recentDictation = recentDictation
        scopeKind = recentDictation?.applicationBundleID?.isEmpty == false ? .application : .global
        saveAction = { draft in
            _ = try await learningStore.upsertMemory(draft)
            return try await learningStore.memorySnapshot()
        }
        self.onLearningChanged = onLearningChanged
        onSaved = {
            Task { await learningMetrics.increment(.teachWordSaves) }
        }
    }

    init(
        recentDictation: RecentDictation?,
        saveAction: @escaping SaveAction,
        onLearningChanged: @escaping (MemorySnapshot) -> Void = { _ in },
        onSaved: @escaping () -> Void = {}
    ) {
        self.recentDictation = recentDictation
        scopeKind = recentDictation?.applicationBundleID?.isEmpty == false ? .application : .global
        self.saveAction = saveAction
        self.onLearningChanged = onLearningChanged
        self.onSaved = onSaved
    }

    var canSave: Bool {
        let heard = heardPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = preferredPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return !isSaving
            && !heard.isEmpty
            && !preferred.isEmpty
            && heard != preferred
            && mappingSafety == .direct
    }

    var mappingSafety: CorrectionMappingSafety {
        let heard = heardPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let preferred = preferredPhrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty, !preferred.isEmpty, heard != preferred else { return .direct }
        return mappingPolicy.safety(for: CorrectionProposal(heardForm: heard, preferredForm: preferred))
    }

    var applicationName: String? {
        recentDictation?.applicationName
    }

    var canUseApplicationScope: Bool {
        recentDictation?.applicationBundleID?.isEmpty == false
    }

    func save() async {
        guard canSave else { return }
        isSaving = true
        errorMessage = ""
        defer { isSaving = false }

        let effectiveScope: LearningScopeKind = scopeKind == .application && canUseApplicationScope
            ? .application
            : .global
        let draft = LearningMemoryDraft(
            heardForm: heardPhrase,
            preferredForm: preferredPhrase,
            scopeKind: effectiveScope,
            scopeValue: effectiveScope == .application ? recentDictation?.applicationBundleID ?? "" : "",
            language: recentDictation?.language ?? "auto",
            status: .active,
            origin: .seeded
        )

        do {
            let snapshot = try await saveAction(draft)
            onLearningChanged(snapshot)
            onSaved()
            onDismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() {
        onDismiss()
    }
}

private struct QuickVocabularyView: View {
    @ObservedObject var model: QuickVocabularyModel
    @FocusState private var focusedField: Field?

    private enum Field {
        case heard
        case preferred
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Teach Flint")
                    .font(.system(size: 25, weight: .semibold))
                Text("Add one word or phrase without leaving your flow. It becomes active on the next dictation.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Flint hears")
                    .font(.system(size: 12, weight: .semibold))
                TextField("next jay ess", text: $model.heardPhrase)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .heard)
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("Flint should write")
                    .font(.system(size: 12, weight: .semibold))
                TextField("Next.js", text: $model.preferredPhrase)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedField, equals: .preferred)
            }

            Picker("Use this vocabulary", selection: $model.scopeKind) {
                if let applicationName = model.applicationName, model.canUseApplicationScope {
                    Text("Only in \(applicationName)").tag(LearningScopeKind.application)
                }
                Text("Everywhere").tag(LearningScopeKind.global)
            }
            .pickerStyle(.segmented)

            if model.mappingSafety == .contextRequired {
                Label(
                    "That spoken form is also a common phrase. Use a distinctive form such as “next jay ess” so Flint does not break normal dictation.",
                    systemImage: "exclamationmark.shield.fill"
                )
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            }

            if !model.errorMessage.isEmpty {
                Text(model.errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { model.cancel() }
                    .keyboardShortcut(.cancelAction)
                Button(model.isSaving ? "Saving…" : "Teach Flint") {
                    Task { await model.save() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(!model.canSave)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 330)
        .onAppear {
            DispatchQueue.main.async { focusedField = .heard }
        }
    }
}
