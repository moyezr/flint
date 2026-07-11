import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class PrivacyWindowController {
    private let window: NSWindow
    private let model: PrivacyDashboardModel

    init(
        privacyManager: PrivacyManager,
        onDeleteAllLocalData: @escaping () -> Void
    ) {
        model = PrivacyDashboardModel(
            privacyManager: privacyManager,
            onDeleteAllLocalData: onDeleteAllLocalData
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Flint Privacy"
        window.contentView = NSHostingView(rootView: PrivacyDashboardView(model: model))
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        model.refresh()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@MainActor
private final class PrivacyDashboardModel: ObservableObject {
    @Published var snapshot: PrivacyDashboardSnapshot
    @Published var deletionMessage = ""
    @Published var deletionError = ""
    @Published var historyEnabled: Bool
    @Published var historyCount = 0
    @Published var historyEntries: [HistoryEntry] = []
    @Published var historyMessage = ""
    @Published var historyError = ""

    private let privacyManager: PrivacyManager
    private let onDeleteAllLocalData: () -> Void

    init(
        privacyManager: PrivacyManager,
        onDeleteAllLocalData: @escaping () -> Void
    ) {
        self.privacyManager = privacyManager
        self.onDeleteAllLocalData = onDeleteAllLocalData
        let initialSnapshot = privacyManager.snapshot()
        snapshot = initialSnapshot
        historyEnabled = initialSnapshot.statusRows.first { $0.id == "history" }?.value == "On"
        historyCount = privacyManager.historyCount()
        reloadHistory()
    }

    func refresh() {
        snapshot = privacyManager.snapshot()
        historyEnabled = snapshot.statusRows.first { $0.id == "history" }?.value == "On"
        historyCount = privacyManager.historyCount()
        reloadHistory()
    }

    func setHistoryEnabled(_ enabled: Bool) {
        privacyManager.setHistoryEnabled(enabled)
        refresh()
        historyMessage = enabled ? "History enabled." : "History disabled."
        historyError = ""
    }

    func deleteHistoryEntry(_ entry: HistoryEntry) {
        do {
            try privacyManager.deleteHistoryEntry(id: entry.id)
            refresh()
            historyMessage = "Deleted history entry."
            historyError = ""
        } catch {
            historyMessage = ""
            historyError = error.localizedDescription
        }
    }

    func deleteAllHistory() {
        do {
            try privacyManager.deleteAllHistory()
            refresh()
            historyMessage = "Deleted all history entries."
            historyError = ""
        } catch {
            historyMessage = ""
            historyError = error.localizedDescription
        }
    }

    func exportHistory() {
        let panel = NSSavePanel()
        panel.title = "Export History"
        panel.nameFieldStringValue = "Flint History.json"
        panel.allowedContentTypes = [.json]

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try privacyManager.exportHistory(to: url)
            historyMessage = "Exported history to \(url.path)."
            historyError = ""
        } catch {
            historyMessage = ""
            historyError = error.localizedDescription
        }
    }

    func deleteAllLocalData() {
        do {
            let result = try privacyManager.deleteAllLocalData()
            onDeleteAllLocalData()
            refresh()
            deletionError = ""
            deletionMessage = "Deleted \(result.customReplacementCount) vocabulary entries, \(result.installedModelCount) installed model references, \(result.historyEntryCount) history entries, \(result.appModeRuleCount) app mode rules, and license activation. Settings are back to defaults."
        } catch {
            deletionMessage = ""
            deletionError = error.localizedDescription
        }
    }

    private func reloadHistory() {
        do {
            historyEntries = try privacyManager.historyEntries(limit: 50)
            historyError = ""
        } catch {
            historyEntries = []
            historyError = error.localizedDescription
        }
    }
}

private struct PrivacyDashboardView: View {
    @ObservedObject var model: PrivacyDashboardModel
    @State private var isConfirmingDelete = false
    @State private var isConfirmingHistoryDelete = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Privacy")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Flint is designed around local dictation. This dashboard shows what is stored and what can be cleared.")
                        .foregroundStyle(.secondary)
                }

                PrivacySection(title: "Processing") {
                    VStack(spacing: 10) {
                        ForEach(model.snapshot.statusRows) { row in
                            StatusRow(title: row.title, value: row.value, detail: row.detail)
                        }
                    }
                }

                PrivacySection(title: "Permissions") {
                    VStack(spacing: 10) {
                        ForEach(model.snapshot.permissionStatuses, id: \.kind.title) { status in
                            StatusRow(
                                title: status.title,
                                value: status.isReady ? "Ready" : "Needed",
                                detail: "\(status.statusLine). \(status.explanation)"
                            )
                        }
                    }
                }

                PrivacySection(title: "Data Locations") {
                    VStack(spacing: 10) {
                        ForEach(model.snapshot.dataLocations) { location in
                            DataLocationRow(location: location)
                        }
                    }
                }

                PrivacySection(title: "History") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Store dictation history", isOn: Binding(
                            get: { model.historyEnabled },
                            set: { model.setHistoryEnabled($0) }
                        ))
                        .toggleStyle(.checkbox)

                        HStack(spacing: 8) {
                            Text("\(model.historyCount) entries stored")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Export") {
                                model.exportHistory()
                            }
                            .disabled(model.historyEntries.isEmpty)
                            Button("Delete All") {
                                isConfirmingHistoryDelete = true
                            }
                            .disabled(model.historyEntries.isEmpty)
                        }

                        if model.historyEntries.isEmpty {
                            Text("No history entries stored.")
                                .foregroundStyle(.secondary)
                        } else {
                            VStack(spacing: 8) {
                                ForEach(model.historyEntries) { entry in
                                    HistoryEntryRow(entry: entry) {
                                        model.deleteHistoryEntry(entry)
                                    }
                                }
                            }
                        }

                        if !model.historyMessage.isEmpty {
                            Text(model.historyMessage)
                                .foregroundStyle(.secondary)
                        }
                        if !model.historyError.isEmpty {
                            Text(model.historyError)
                                .foregroundStyle(.red)
                        }
                    }
                }

                PrivacySection(title: "Delete Local Data") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deletes custom vocabulary, cached model files, installed model references, history entries, app mode rules, license activation, and resets app settings to defaults.")
                            .foregroundStyle(.secondary)

                        Button("Delete All Local Data") {
                            isConfirmingDelete = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)

                        if !model.deletionMessage.isEmpty {
                            Text(model.deletionMessage)
                                .foregroundStyle(.secondary)
                        }
                        if !model.deletionError.isEmpty {
                            Text(model.deletionError)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 680, minHeight: 620)
        .alert("Delete all local data?", isPresented: $isConfirmingDelete) {
            Button("Delete All Local Data", role: .destructive) {
                model.deleteAllLocalData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This resets settings to defaults, removes custom vocabulary, deletes cached model contents, clears installed model references, deletes history and app mode rules, and clears license activation.")
        }
        .alert("Delete all history?", isPresented: $isConfirmingHistoryDelete) {
            Button("Delete All History", role: .destructive) {
                model.deleteAllHistory()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes stored transcript history entries. Raw audio is never stored by history.")
        }
    }
}

private struct PrivacySection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            content
        }
    }
}

private struct StatusRow: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .overlay(
            Rectangle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct DataLocationRow: View {
    let location: PrivacyDataLocation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(location.title)
                .font(.headline)
            Text(location.path)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
            Text(location.detail)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay(
            Rectangle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}

private struct HistoryEntryRow: View {
    let entry: HistoryEntry
    let onDelete: () -> Void

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.finalText)
                    .font(.headline)
                    .lineLimit(2)
                Text(metadata)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Text("Raw: \(entry.rawTranscript)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("Delete", role: .destructive) {
                onDelete()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay(
            Rectangle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var metadata: String {
        let appName = entry.activeAppName ?? "Unknown app"
        return "\(Self.dateFormatter.string(from: entry.createdAt)) - \(appName) - \(entry.mode) - \(entry.durationMS) ms - \(entry.modelName) - \(entry.language)"
    }
}
