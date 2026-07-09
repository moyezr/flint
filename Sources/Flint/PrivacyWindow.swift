import AppKit
import SwiftUI

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

    private let privacyManager: PrivacyManager
    private let onDeleteAllLocalData: () -> Void

    init(
        privacyManager: PrivacyManager,
        onDeleteAllLocalData: @escaping () -> Void
    ) {
        self.privacyManager = privacyManager
        self.onDeleteAllLocalData = onDeleteAllLocalData
        snapshot = privacyManager.snapshot()
    }

    func refresh() {
        snapshot = privacyManager.snapshot()
    }

    func deleteAllLocalData() {
        do {
            let result = try privacyManager.deleteAllLocalData()
            onDeleteAllLocalData()
            refresh()
            deletionError = ""
            deletionMessage = "Deleted \(result.customReplacementCount) vocabulary entries and \(result.installedModelCount) installed model references. Settings are back to defaults."
        } catch {
            deletionMessage = ""
            deletionError = error.localizedDescription
        }
    }
}

private struct PrivacyDashboardView: View {
    @ObservedObject var model: PrivacyDashboardModel
    @State private var isConfirmingDelete = false

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

                PrivacySection(title: "Delete Local Data") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Deletes custom vocabulary and cached model files, clears installed model references, and resets app settings to defaults.")
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
            Text("This resets settings to defaults, removes custom vocabulary, deletes cached model contents, and clears installed model references.")
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
