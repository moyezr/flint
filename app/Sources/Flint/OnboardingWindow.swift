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
        modelPreparationAction: @escaping (ModelTier) async throws -> Void = { _ in },
        onTestDictation: @escaping () -> Void,
        onSettingsChanged: @escaping (AppSettings) -> Void,
        onPermissionsChanged: @escaping () -> Void,
        onComplete: @escaping () -> Void,
        initialStep: OnboardingStep = .welcome
    ) {
        let modelRecommendation = ModelRecommendation.current
        flow = OnboardingFlow(
            store: settingsStore,
            permissionSnapshotProvider: { permissionManager.snapshot() },
            permissionPromptAction: { await permissionManager.requestMissingPermissions() },
            permissionRequestAction: { kind in await permissionManager.requestPermission(kind) },
            permissionRecoveryAction: { kind in
                guard let url = PermissionSettingsRoute.url(for: kind) else { return }
                NSWorkspace.shared.open(url)
            },
            modelInstalledProvider: { tier in modelManager.metadata(for: tier).isInstalled },
            modelDownloadAction: { tier, reportProgress in
                _ = try await modelManager.downloadModel(for: tier) { progress in
                    Task { @MainActor in
                        reportProgress(progress.fractionCompleted)
                    }
                }
                try await modelPreparationAction(tier)
            },
            onPermissionsChanged: onPermissionsChanged,
            onSettingsChanged: onSettingsChanged,
            onComplete: onComplete,
            recommendedModelTier: modelRecommendation.tier,
            allowsModelSelection: modelRecommendation.allowsOnboardingChoice,
            initialStep: initialStep
        )

        let rootView = OnboardingView(
            flow: flow,
            modelManager: modelManager,
            onTestDictation: onTestDictation
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 580),
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
        ZStack {
            onboardingBackground

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 12) {
                    FlintOnboardingMark()
                        .frame(width: 42, height: 42)
                        .shadow(color: FlintBrand.signal.opacity(0.22), radius: 10, y: 4)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("FLINT SETUP")
                            .font(.caption.weight(.bold))
                            .tracking(1.4)
                            .foregroundStyle(FlintBrand.signal)
                        Text("Step \(currentStepNumber) of \(OnboardingStep.allCases.count)")
                            .font(.callout)
                            .foregroundStyle(FlintBrand.muted)
                    }

                    Spacer()

                    HStack(spacing: 7) {
                        ForEach(OnboardingStep.allCases, id: \.self) { step in
                            Capsule()
                                .fill(stepProgressColor(step))
                                .frame(width: step == flow.currentStep ? 30 : 12, height: 7)
                                .animation(.easeInOut(duration: 0.22), value: flow.currentStep)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: stepIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(FlintBrand.signal)
                            .frame(width: 40, height: 40)
                            .background(FlintBrand.signal.opacity(0.1), in: Circle())

                        VStack(alignment: .leading, spacing: 4) {
                            Text(flow.currentStep.title)
                                .font(.system(size: 29, weight: .bold, design: .rounded))
                            Text(stepSubtitle)
                                .font(.callout)
                                .foregroundStyle(FlintBrand.muted)
                        }
                    }

                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(26)
                .background(FlintBrand.mist.opacity(0.58), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(FlintBrand.line, lineWidth: 1)
                }
                .shadow(color: FlintBrand.deep.opacity(0.08), radius: 18, y: 8)

                HStack {
                    Button("Back") {
                        flow.back()
                    }
                    .buttonStyle(.bordered)
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
                .controlSize(.large)
                .padding(.horizontal, 4)
            }
            .padding(24)
        }
        .tint(FlintBrand.signal)
        .foregroundStyle(FlintBrand.ink)
        .preferredColorScheme(.light)
        .frame(minWidth: 780, minHeight: 580)
        .task(id: flow.currentStep) {
            await flow.promptForPermissionsIfNeeded()
            await flow.monitorPermissionChanges()
        }
    }

    private var onboardingBackground: some View {
        ZStack {
            FlintBrand.paper
            RadialGradient(
                colors: [FlintBrand.signal.opacity(0.09), .clear],
                center: .topLeading,
                startRadius: 10,
                endRadius: 430
            )
            Circle()
                .fill(FlintBrand.signal.opacity(0.045))
                .frame(width: 180, height: 180)
                .blur(radius: 2)
                .offset(x: 330, y: -250)
            Circle()
                .stroke(FlintBrand.signal.opacity(0.07), lineWidth: 18)
                .frame(width: 130, height: 130)
                .offset(x: -360, y: 260)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.currentStep {
        case .welcome:
            VStack(alignment: .leading, spacing: 18) {
                Text("Talk naturally. Flint keeps up and puts the words right where you need them.")
                    .font(.title3.weight(.medium))
                Text("This setup picks a shortcut, requests the macOS permissions Flint needs, and chooses a local model.")
                    .foregroundStyle(FlintBrand.muted)
                HStack(spacing: 10) {
                    OnboardingFeaturePill(icon: "lock.shield", label: "Private")
                    OnboardingFeaturePill(icon: "wifi.slash", label: "Works offline")
                    OnboardingFeaturePill(icon: "text.cursor", label: "Types anywhere")
                }
            }
        case .privacy:
            VStack(alignment: .leading, spacing: 10) {
                OnboardingInfoRow(
                    icon: "macbook",
                    title: "Transcribed on this Mac",
                    detail: "Your recordings and transcript processing stay local."
                )
                OnboardingInfoRow(
                    icon: "eye.slash",
                    title: "No telemetry by default",
                    detail: "Onboarding does not enable history, telemetry, or license checks."
                )
                OnboardingInfoRow(
                    icon: "hand.raised",
                    title: "Only the permissions Flint needs",
                    detail: "Recording, detecting your shortcut, and inserting text."
                )
                Text("Packaged betas make one small release check at most daily when internet is available.")
                    .font(.caption)
                    .foregroundStyle(FlintBrand.muted.opacity(0.78))
            }
        case .shortcut:
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 14) {
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
                }
                .padding(16)
                .background(FlintBrand.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 14))
                Text(flow.settings.shortcutSettings.readyHint)
                    .font(.headline)
                    .foregroundStyle(FlintBrand.signal)
            }
            .frame(maxWidth: 420, alignment: .leading)
        case .permissions:
            VStack(alignment: .leading, spacing: 14) {
                ForEach(flow.permissionSnapshot.statuses, id: \.kind.title) { status in
                    PermissionStatusRow(
                        status: status,
                        onResolve: {
                            Task { await flow.recoverPermission(status.kind) }
                        }
                    )
                }
                HStack {
                    Button(flow.isPromptingForPermissions ? "Prompting..." : "Prompt for Missing Permissions") {
                        Task { await flow.recoverMissingPermissions() }
                    }
                    .disabled(flow.isPromptingForPermissions)

                    Spacer()

                    Button("Quit Flint") {
                        NSApp.terminate(nil)
                    }
                }
                Text(permissionReadinessMessage)
                    .foregroundStyle(FlintBrand.muted)
                    .font(.callout)
                if flow.permissionSnapshot.missingCount > 0 {
                    Text("Turn on the switch next to Flint in System Settings. This screen checks automatically and changes to Ready as soon as macOS grants access.")
                        .foregroundStyle(FlintBrand.muted.opacity(0.82))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Flint needs Microphone and Accessibility only. A separate Input Monitoring grant is not required.")
                        .foregroundStyle(FlintBrand.muted.opacity(0.82))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        case .model:
            VStack(alignment: .leading, spacing: 14) {
                if flow.allowsModelSelection {
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
                } else {
                    let metadata = modelManager.metadata(for: flow.settings.selectedModelTier)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(metadata.displayName)
                                .font(.headline)
                            Spacer()
                            Text(metadata.sizeLabel)
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(FlintBrand.muted)
                        }
                        Text("Recommended for precise outputs on this Apple Silicon Mac.")
                            .foregroundStyle(FlintBrand.muted)
                    }
                    .padding(14)
                    .background(FlintBrand.signal.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

                Button(downloadButtonTitle) {
                    Task { await flow.downloadSelectedModel() }
                }
                .disabled(flow.isDownloadingModel || flow.isSelectedModelInstalled)

                if flow.isDownloadingModel {
                    VStack(alignment: .leading, spacing: 8) {
                        ProgressView(value: flow.modelDownloadProgress, total: 1)
                            .progressViewStyle(.linear)

                        HStack {
                            Text(modelDownloadProgressLabel)
                            Spacer()
                            Text("\(Int((flow.modelDownloadProgress * 100).rounded()))%")
                                .monospacedDigit()
                        }
                        .font(.callout)
                        .foregroundStyle(FlintBrand.muted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(modelDownloadProgressLabel)
                    .accessibilityValue("\(Int((flow.modelDownloadProgress * 100).rounded())) percent")
                }

                if !flow.modelDownloadStatus.isEmpty {
                    Text(flow.modelDownloadStatus)
                        .foregroundStyle(FlintBrand.muted)
                }

                Text(modelReadinessMessage)
                    .foregroundStyle(FlintBrand.muted)
                Text("The selected model is saved as your default. You can manage models later from the Models menu.")
                    .foregroundStyle(FlintBrand.muted)
            }
            .frame(maxWidth: 560, alignment: .leading)
        case .testDictation:
            VStack(alignment: .leading, spacing: 12) {
                Text(flow.settings.shortcutSettings.readyHint)
                TextEditor(text: $testText)
                    .font(.system(size: 14))
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(FlintBrand.ink.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(FlintBrand.signal.opacity(0.25), lineWidth: 1)
                    )
                Button("Start/Stop Test Dictation") {
                    onTestDictation()
                }
                Text(testDictationInstruction)
                    .foregroundStyle(FlintBrand.muted)
                Text("Finish is available after permissions are ready and the selected model is installed.")
                    .foregroundStyle(FlintBrand.muted)
            }
        }
    }

    private var currentStepNumber: Int {
        (OnboardingStep.allCases.firstIndex(of: flow.currentStep) ?? 0) + 1
    }

    private var stepIcon: String {
        switch flow.currentStep {
        case .welcome: return "sparkles"
        case .privacy: return "lock.shield.fill"
        case .shortcut: return "keyboard"
        case .permissions: return "checkmark.shield"
        case .model: return "cpu"
        case .testDictation: return "quote.bubble"
        }
    }

    private var stepSubtitle: String {
        switch flow.currentStep {
        case .welcome: return "A quick setup, then you can dictate anywhere."
        case .privacy: return "Your voice stays yours."
        case .shortcut: return "Choose what feels natural under your fingers."
        case .permissions: return "macOS asks before Flint can listen or type."
        case .model: return "The speech model runs locally on your Mac."
        case .testDictation: return "Say a sentence and watch it appear."
        }
    }

    private func stepProgressColor(_ step: OnboardingStep) -> Color {
        guard let currentIndex = OnboardingStep.allCases.firstIndex(of: flow.currentStep),
              let stepIndex = OnboardingStep.allCases.firstIndex(of: step) else {
            return Color(nsColor: .separatorColor)
        }
        return stepIndex <= currentIndex ? FlintBrand.signal : FlintBrand.line
    }

    private var downloadButtonTitle: String {
        let metadata = modelManager.metadata(for: flow.settings.selectedModelTier)
        if flow.isDownloadingModel {
            return flow.modelDownloadProgress >= 1 ? "Preparing \(metadata.displayName)..." : "Downloading \(metadata.displayName)..."
        }
        return metadata.isInstalled
            ? "\(metadata.displayName) Installed"
            : "Download \(metadata.displayName)"
    }

    private var modelDownloadProgressLabel: String {
        flow.modelDownloadProgress >= 1
            ? "Preparing model for first use"
            : "Downloading model"
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

    private var testDictationInstruction: String {
        switch flow.settings.shortcutSettings.behavior {
        case .pushToTalk:
            return "Click in the field above, then hold the selected shortcut to dictate and release it to stop. The test button starts and stops dictation manually. Press Esc to cancel."
        case .toggle:
            return "Click in the field above, then press the selected shortcut to start and press it again to stop. The test button starts and stops dictation manually. Press Esc to cancel."
        }
    }
}

private struct FlintOnboardingMark: View {
    var body: some View {
        Image(nsImage: NSApplication.shared.applicationIconImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(FlintBrand.signal.opacity(0.22), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}

private struct PermissionStatusRow: View {
    let status: PermissionStatus
    let onResolve: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status.statusLine)
                    .font(.headline)
                Spacer()
                if status.isReady {
                    Text("Ready")
                        .foregroundStyle(Color.green)
                } else {
                    Button(status.kind == .accessibility ? "Turn On in Settings" : "Open Settings", action: onResolve)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(FlintBrand.signal)
                }
            }
            Text(status.explanation)
                .foregroundStyle(FlintBrand.muted)
        }
        .padding(12)
        .background(FlintBrand.ink.opacity(0.04), in: RoundedRectangle(cornerRadius: 13))
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .stroke(status.isReady ? Color.green.opacity(0.22) : FlintBrand.signal.opacity(0.22), lineWidth: 1)
        }
    }
}

private struct OnboardingFeaturePill: View {
    let icon: String
    let label: String

    var body: some View {
        Label(label, systemImage: icon)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .foregroundStyle(FlintBrand.ink)
            .background(FlintBrand.signal.opacity(0.08), in: Capsule())
    }
}

private struct OnboardingInfoRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(FlintBrand.signal)
                .frame(width: 32, height: 32)
                .background(FlintBrand.signal.opacity(0.08), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(FlintBrand.muted)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlintBrand.ink.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
    }
}
