import AppKit
import SwiftUI

@MainActor
final class LicenseWindowController {
    private let window: NSWindow
    private let model: LicenseWindowModel

    init(
        licenseManager: LicenseManager = LicenseManager(),
        activationClient: @escaping (String) async throws -> LicenseActivationResponse = LicenseActivationService.notConfiguredClient
    ) {
        model = LicenseWindowModel(
            licenseManager: licenseManager,
            activationClient: activationClient
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Flint License"
        window.contentView = NSHostingView(rootView: LicenseWindowView(model: model))
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
final class LicenseWindowModel: ObservableObject {
    @Published var licenseKey = ""
    @Published private(set) var statusTitle = "Inactive"
    @Published private(set) var statusDetail = "No license activation is stored."
    @Published private(set) var message = ""
    @Published private(set) var errorMessage = ""
    @Published private(set) var isActivating = false

    private let licenseManager: LicenseManager
    private let activationService: LicenseActivationService

    init(
        licenseManager: LicenseManager = LicenseManager(),
        activationClient: @escaping (String) async throws -> LicenseActivationResponse = LicenseActivationService.notConfiguredClient
    ) {
        self.licenseManager = licenseManager
        activationService = LicenseActivationService(
            client: activationClient,
            licenseManager: licenseManager
        )
        refresh()
    }

    func refresh() {
        do {
            apply(record: try licenseManager.load())
            errorMessage = ""
        } catch {
            apply(record: .inactive)
            errorMessage = error.localizedDescription
        }
    }

    func activate() async {
        message = ""
        errorMessage = ""
        isActivating = true
        defer { isActivating = false }

        do {
            let record = try await activationService.activate(licenseKey: licenseKey)
            licenseKey = ""
            apply(record: record)
            message = "License activated."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func clearActivation() {
        do {
            try licenseManager.clear()
            licenseKey = ""
            apply(record: .inactive)
            message = "Activation cleared."
            errorMessage = ""
        } catch {
            message = ""
            errorMessage = error.localizedDescription
        }
    }

    private func apply(record: LicenseRecord) {
        switch record.status {
        case .activated:
            statusTitle = "Activated"
            statusDetail = activeDetail(for: record)
        case .offlineValid:
            statusTitle = "Offline Valid"
            statusDetail = activeDetail(for: record)
        case .inactive:
            statusTitle = "Inactive"
            statusDetail = "No license activation is stored."
        case .expired:
            statusTitle = "Expired"
            statusDetail = "The stored activation is expired."
        case .revoked:
            statusTitle = "Revoked"
            statusDetail = "The stored activation has been revoked."
        }
    }

    private func activeDetail(for record: LicenseRecord) -> String {
        var lines: [String] = []
        if let activationID = record.activationID {
            lines.append("Activation ID: \(activationID)")
        }
        if let licenseKeyHash = record.licenseKeyHash {
            lines.append("License hash: \(shortHash(licenseKeyHash))")
        }
        if let lastCheckedAt = record.lastCheckedAt {
            lines.append("Last checked: \(Self.dateFormatter.string(from: lastCheckedAt))")
        }
        return lines.joined(separator: "\n")
    }

    private func shortHash(_ hash: String) -> String {
        guard hash.count > 12 else {
            return hash
        }
        return "\(hash.prefix(6))...\(hash.suffix(6))"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct LicenseWindowView: View {
    @ObservedObject var model: LicenseWindowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("License")
                    .font(.system(size: 28, weight: .semibold))
                Text("Manage this Mac's Flint activation.")
                    .foregroundStyle(.secondary)
            }

            LicenseStatusPanel(
                title: model.statusTitle,
                detail: model.statusDetail
            )

            VStack(alignment: .leading, spacing: 8) {
                Text("License Key")
                    .font(.system(size: 16, weight: .semibold))
                SecureField("Enter license key", text: $model.licenseKey)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(model.isActivating ? "Activating..." : "Activate") {
                        Task { await model.activate() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isActivating)

                    Button("Clear Activation", role: .destructive) {
                        model.clearActivation()
                    }
                    .disabled(model.isActivating)

                    Spacer()
                }
            }

            if !model.message.isEmpty {
                Text(model.message)
                    .foregroundStyle(.secondary)
            }
            if !model.errorMessage.isEmpty {
                Text(model.errorMessage)
                    .foregroundStyle(.red)
            }

            Spacer()
        }
        .padding(28)
        .frame(minWidth: 560, minHeight: 420, alignment: .topLeading)
    }
}

private struct LicenseStatusPanel: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(detail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .overlay(
            Rectangle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
