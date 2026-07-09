import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    private let window: NSWindow
    private let flow: OnboardingFlow

    init(
        settingsStore: AppSettingsStore,
        permissionManager: PermissionManager,
        modelManager: ModelManager,
        onTestDictation: @escaping () -> Void,
        onSettingsChanged: @escaping (AppSettings) -> Void,
        onComplete: @escaping () -> Void
    ) {
        flow = OnboardingFlow(
            store: settingsStore,
            permissionSnapshotProvider: { permissionManager.snapshot() },
            permissionPromptAction: { await permissionManager.requestMissingPermissions() },
            modelInstalledProvider: { tier in modelManager.metadata(for: tier).isInstalled },
            modelDownloadAction: { tier in _ = try await modelManager.downloadModel(for: tier) },
            onSettingsChanged: onSettingsChanged,
            onComplete: onComplete
        )

        let rootView = OnboardingView(
            flow: flow,
            modelManager: modelManager,
            onTestDictation: onTestDictation
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Flint Onboarding"
        window.contentView = NSHostingView(rootView: rootView)
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() {
        window.close()
    }
}

private struct OnboardingView: View {
    @ObservedObject var flow: OnboardingFlow
    let modelManager: ModelManager
    let onTestDictation: () -> Void
    @State private var testText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    Rectangle()
                        .fill(stepProgressColor(step))
                        .frame(height: 3)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)

            VStack(alignment: .leading, spacing: 20) {
                Text(flow.currentStep.title)
                    .font(.system(size: 28, weight: .semibold))

                stepContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(28)

            Divider()

            HStack {
                Button("Back") {
                    flow.back()
                }
                .disabled(!flow.canGoBack)

                Spacer()

                if flow.isFinalStep {
                    Button("Finish") {
                        flow.finish()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!flow.canFinish)
                } else {
                    Button("Next") {
                        flow.next()
                    }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!flow.canAdvance)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 720, minHeight: 520)
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.currentStep {
        case .welcome:
            VStack(alignment: .leading, spacing: 12) {
                Text("Flint turns speech into text locally and inserts it where you are typing.")
                Text("This setup picks a shortcut, requests the macOS permissions Flint needs, and chooses a local model.")
                    .foregroundStyle(.secondary)
            }
        case .privacy:
            VStack(alignment: .leading, spacing: 12) {
                Text("Your audio is transcribed on this Mac.")
                Text("This onboarding flow does not enable history, telemetry, license checks, or update behavior.")
                    .foregroundStyle(.secondary)
                Text("Permissions are requested only for recording, detecting the shortcut, and inserting text.")
                    .foregroundStyle(.secondary)
            }
        case .shortcut:
            VStack(alignment: .leading, spacing: 18) {
                Picker("Shortcut", selection: Binding(
                    get: { flow.settings.shortcutSettings.option },
                    set: { flow.selectShortcut($0) }
                )) {
                    ForEach(ShortcutOption.allCases, id: \.rawValue) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                Picker("Input Behavior", selection: Binding(
                    get: { flow.settings.shortcutSettings.behavior },
                    set: { flow.selectShortcutBehavior($0) }
                )) {
                    ForEach(ShortcutInputBehavior.allCases, id: \.rawValue) { behavior in
                        Text(behavior.displayName).tag(behavior)
                    }
                }
                Text(flow.settings.shortcutSettings.readyHint)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 420, alignment: .leading)
        case .permissions:
            VStack(alignment: .leading, spacing: 14) {
                ForEach(flow.permissionSnapshot.statuses, id: \.kind.title) { status in
                    PermissionStatusRow(status: status)
                }
                HStack {
                    Button(flow.isPromptingForPermissions ? "Prompting..." : "Prompt for Missing Permissions") {
                        Task { await flow.promptForPermissions() }
                    }
                    .disabled(flow.isPromptingForPermissions)

                    Button("Refresh") {
                        flow.refreshPermissionSnapshot()
                    }
                }
                Text(permissionReadinessMessage)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        case .model:
            VStack(alignment: .leading, spacing: 14) {
                Picker("Default Model", selection: Binding(
                    get: { flow.settings.selectedModelTier },
                    set: { tier in
                        flow.selectModelTier(tier)
                    }
                )) {
                    ForEach(ModelTier.allCases, id: \.rawValue) { tier in
                        let metadata = modelManager.metadata(for: tier)
                        Text("\(metadata.displayName) - \(metadata.sizeLabel) - \(metadata.hardwareLabel)").tag(tier)
                    }
                }

                Button(flow.isDownloadingModel ? "Downloading..." : downloadButtonTitle) {
                    Task { await flow.downloadSelectedModel() }
                }
                .disabled(flow.isDownloadingModel)

                if !flow.modelDownloadStatus.isEmpty {
                    Text(flow.modelDownloadStatus)
                        .foregroundStyle(.secondary)
                }

                Text(modelReadinessMessage)
                    .foregroundStyle(.secondary)
                Text("The selected model is saved as your default. You can manage models later from the Models menu.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 560, alignment: .leading)
        case .testDictation:
            VStack(alignment: .leading, spacing: 12) {
                Text(flow.settings.shortcutSettings.readyHint)
                TextEditor(text: $testText)
                    .font(.system(size: 14))
                    .frame(height: 120)
                    .overlay(
                        Rectangle()
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                    )
                Button("Start/Stop Test Dictation") {
                    onTestDictation()
                }
                Text("Click in the field above, then use the selected shortcut or the test button. Use the same action again to stop, or press Esc to cancel.")
                    .foregroundStyle(.secondary)
                Text("Finish is available after permissions are ready and the selected model is installed.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stepProgressColor(_ step: OnboardingStep) -> Color {
        guard let currentIndex = OnboardingStep.allCases.firstIndex(of: flow.currentStep),
              let stepIndex = OnboardingStep.allCases.firstIndex(of: step) else {
            return Color(nsColor: .separatorColor)
        }
        return stepIndex <= currentIndex ? Color.orange : Color(nsColor: .separatorColor)
    }

    private var downloadButtonTitle: String {
        let metadata = modelManager.metadata(for: flow.settings.selectedModelTier)
        return metadata.isInstalled
            ? "Download \(metadata.displayName) Again"
            : "Download \(metadata.displayName)"
    }

    private var permissionReadinessMessage: String {
        flow.permissionSnapshot.missingCount == 0
            ? "Permissions are ready."
            : "Grant the missing permissions before continuing."
    }

    private var modelReadinessMessage: String {
        flow.isSelectedModelInstalled
            ? "\(flow.settings.selectedModelTier.displayName) model is installed."
            : "Download the selected model before continuing."
    }
}

private struct PermissionStatusRow: View {
    let status: PermissionStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status.statusLine)
                    .font(.headline)
                Spacer()
                Text(status.isReady ? "Ready" : "Needed")
                    .foregroundStyle(status.isReady ? .green : .orange)
            }
            Text(status.explanation)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .overlay(
            Rectangle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
