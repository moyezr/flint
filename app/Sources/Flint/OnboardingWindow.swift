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
        FlintTypography.registerBundledFonts()
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
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 610),
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

struct OnboardingView: View {
    @ObservedObject var flow: OnboardingFlow
    let modelManager: ModelManager
    let onTestDictation: () -> Void
    @State private var testText = ""

    var body: some View {
        ZStack {
            onboardingBackground

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    FlintOnboardingWordmark()

                    Rectangle()
                        .fill(FlintBrand.line)
                        .frame(width: 1, height: 24)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("SETUP")
                            .font(FlintTypography.mono(size: 10, weight: .semibold))
                            .tracking(1.25)
                            .foregroundStyle(FlintBrand.ink)
                        Text("STEP \(String(format: "%02d", currentStepNumber)) / \(String(format: "%02d", OnboardingStep.allCases.count))")
                            .font(FlintTypography.mono(size: 9, weight: .medium))
                            .tracking(0.6)
                            .foregroundStyle(FlintBrand.muted)
                    }

                    Spacer()

                    HStack(spacing: 7) {
                        ForEach(OnboardingStep.allCases, id: \.self) { step in
                            Rectangle()
                                .fill(stepProgressColor(step))
                                .frame(width: step == flow.currentStep ? 30 : 12, height: 5)
                                .animation(.easeInOut(duration: 0.22), value: flow.currentStep)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: stepIcon)
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(FlintBrand.signal)
                            .frame(width: 42, height: 42)
                            .background(FlintBrand.paper, in: Circle())
                            .overlay {
                                Circle()
                                    .stroke(FlintBrand.signal, lineWidth: 1)
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(flow.currentStep.title)
                                .font(FlintTypography.heading(size: 34, weight: .semibold))
                                .tracking(-0.7)
                            Text(stepSubtitle)
                                .font(FlintTypography.body(size: 14))
                                .foregroundStyle(FlintBrand.muted)
                        }
                    }

                    stepContent
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .padding(30)
                .background(FlintBrand.paper.opacity(0.96))
                .overlay {
                    Rectangle()
                        .stroke(FlintBrand.line, lineWidth: 1)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(FlintBrand.signal)
                        .frame(height: 2)
                }

                HStack {
                    Button("Back") {
                        flow.back()
                    }
                    .buttonStyle(OnboardingActionButtonStyle(kind: .secondary))
                    .disabled(!flow.canGoBack)

                    Spacer()

                    if flow.isFinalStep {
                        Button("Finish") {
                            flow.finish()
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(OnboardingActionButtonStyle(kind: .primary))
                        .disabled(!flow.canFinish)
                    } else {
                        Button("Next") {
                            flow.next()
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(OnboardingActionButtonStyle(kind: .primary))
                        .disabled(!flow.canAdvance)
                    }
                }
                .padding(.horizontal, 4)
            }
            .padding(26)
        }
        .tint(FlintBrand.signal)
        .foregroundStyle(FlintBrand.ink)
        .font(FlintTypography.body(size: 14))
        .preferredColorScheme(.light)
        .frame(minWidth: 820, minHeight: 610)
        .task(id: flow.currentStep) {
            await flow.promptForPermissionsIfNeeded()
            await flow.monitorPermissionChanges()
        }
    }

    private var onboardingBackground: some View {
        ZStack {
            FlintBrand.paper
            OnboardingDotPattern()
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var stepContent: some View {
        switch flow.currentStep {
        case .welcome:
            VStack(alignment: .leading, spacing: 18) {
                Text("Talk naturally. Flint keeps up and puts the words right where you need them.")
                    .font(FlintTypography.heading(size: 21, weight: .medium))
                    .tracking(-0.25)
                Text("This setup picks a shortcut, requests the macOS permissions Flint needs, and chooses a local model.")
                    .font(FlintTypography.body(size: 14))
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
                    .font(FlintTypography.mono(size: 10, weight: .medium))
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
                    .font(FlintTypography.body(size: 13, weight: .medium))
                    Picker("Input Behavior", selection: Binding(
                        get: { flow.settings.shortcutSettings.behavior },
                        set: { flow.selectShortcutBehavior($0) }
                    )) {
                        ForEach(ShortcutInputBehavior.allCases, id: \.rawValue) { behavior in
                            Text(behavior.displayName).tag(behavior)
                        }
                    }
                    .font(FlintTypography.body(size: 13, weight: .medium))
                }
                .padding(16)
                .background(FlintBrand.mist.opacity(0.58))
                .overlay {
                    Rectangle()
                        .stroke(FlintBrand.line, lineWidth: 1)
                }
                Text(flow.settings.shortcutSettings.readyHint)
                    .font(FlintTypography.mono(size: 11, weight: .semibold))
                    .tracking(0.35)
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
                    .buttonStyle(OnboardingActionButtonStyle(kind: .primary, compact: true))
                    .disabled(flow.isPromptingForPermissions)

                    Spacer()

                    Button("Quit Flint") {
                        NSApp.terminate(nil)
                    }
                    .buttonStyle(OnboardingActionButtonStyle(kind: .secondary, compact: true))
                }
                Text(permissionReadinessMessage)
                    .foregroundStyle(FlintBrand.muted)
                    .font(FlintTypography.body(size: 13, weight: .medium))
                if flow.permissionSnapshot.missingCount > 0 {
                    Text("Turn on the switch next to Flint in System Settings. This screen checks automatically and changes to Ready as soon as macOS grants access.")
                        .foregroundStyle(FlintBrand.muted.opacity(0.82))
                        .font(FlintTypography.body(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Flint needs Microphone and Accessibility only. A separate Input Monitoring grant is not required.")
                        .foregroundStyle(FlintBrand.muted.opacity(0.82))
                        .font(FlintTypography.body(size: 12))
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
                    .font(FlintTypography.body(size: 13, weight: .medium))
                } else {
                    let metadata = modelManager.metadata(for: flow.settings.selectedModelTier)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(metadata.displayName)
                                .font(FlintTypography.heading(size: 18, weight: .semibold))
                            Spacer()
                            Text(metadata.sizeLabel)
                                .font(FlintTypography.mono(size: 11, weight: .medium))
                                .foregroundStyle(FlintBrand.muted)
                        }
                        Text("Recommended for precise outputs on this Apple Silicon Mac.")
                            .font(FlintTypography.body(size: 13))
                            .foregroundStyle(FlintBrand.muted)
                    }
                    .padding(14)
                    .background(FlintBrand.signal.opacity(0.055))
                    .overlay {
                        Rectangle()
                            .stroke(FlintBrand.signal.opacity(0.55), lineWidth: 1)
                    }
                }

                Button(downloadButtonTitle) {
                    Task { await flow.downloadSelectedModel() }
                }
                .buttonStyle(OnboardingActionButtonStyle(kind: .primary, compact: true))
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
                        .font(FlintTypography.mono(size: 10, weight: .medium))
                        .foregroundStyle(FlintBrand.muted)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(modelDownloadProgressLabel)
                    .accessibilityValue("\(Int((flow.modelDownloadProgress * 100).rounded())) percent")
                }

                if !flow.modelDownloadStatus.isEmpty {
                    Text(flow.modelDownloadStatus)
                        .font(FlintTypography.body(size: 13))
                        .foregroundStyle(FlintBrand.muted)
                }

                Text(modelReadinessMessage)
                    .font(FlintTypography.body(size: 13, weight: .medium))
                    .foregroundStyle(FlintBrand.muted)
                Text("The selected model is saved as your default. You can manage models later from the Models menu.")
                    .font(FlintTypography.body(size: 13))
                    .foregroundStyle(FlintBrand.muted)
            }
            .frame(maxWidth: 560, alignment: .leading)
        case .testDictation:
            VStack(alignment: .leading, spacing: 12) {
                Text(flow.settings.shortcutSettings.readyHint)
                    .font(FlintTypography.mono(size: 11, weight: .semibold))
                TextEditor(text: $testText)
                    .font(FlintTypography.body(size: 14))
                    .frame(height: 120)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(FlintBrand.mist.opacity(0.58))
                    .overlay(
                        Rectangle()
                            .stroke(FlintBrand.line, lineWidth: 1)
                    )
                Button("Start/Stop Test Dictation") {
                    onTestDictation()
                }
                .buttonStyle(OnboardingActionButtonStyle(kind: .primary, compact: true))
                Text(testDictationInstruction)
                    .font(FlintTypography.body(size: 13))
                    .foregroundStyle(FlintBrand.muted)
                Text("Finish is available after permissions are ready and the selected model is installed.")
                    .font(FlintTypography.body(size: 12))
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

private struct OnboardingDotPattern: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 34
            let dotSize: CGFloat = 2
            var x: CGFloat = 17
            while x < size.width {
                var y: CGFloat = 17
                while y < size.height {
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: dotSize, height: dotSize)),
                        with: .color(FlintBrand.signal.opacity(0.095))
                    )
                    y += spacing
                }
                x += spacing
            }
        }
        .accessibilityHidden(true)
    }
}

private struct FlintOnboardingWordmark: View {
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text("FLINT")
                .foregroundStyle(FlintBrand.ink)
            Text("/")
                .foregroundStyle(FlintBrand.signal)
        }
        .font(FlintTypography.heading(size: 22, weight: .bold))
        .tracking(-0.5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Flint")
    }
}

private struct OnboardingActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind
    var compact = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FlintTypography.mono(size: compact ? 10 : 11, weight: .semibold))
            .tracking(0.35)
            .textCase(.uppercase)
            .padding(.horizontal, compact ? 14 : 18)
            .frame(minHeight: compact ? 34 : 40)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor(configuration: configuration))
            .overlay {
                Rectangle()
                    .stroke(borderColor, lineWidth: 1)
            }
            .contentShape(Rectangle())
    }

    private var foregroundColor: Color {
        guard isEnabled else { return FlintBrand.muted.opacity(0.62) }
        switch kind {
        case .primary:
            return FlintBrand.paper
        case .secondary:
            return FlintBrand.ink
        }
    }

    private func backgroundColor(configuration: Configuration) -> Color {
        guard isEnabled else { return FlintBrand.mist.opacity(0.72) }
        switch kind {
        case .primary:
            return configuration.isPressed ? FlintBrand.deep : FlintBrand.signal
        case .secondary:
            return configuration.isPressed ? FlintBrand.mist : FlintBrand.paper
        }
    }

    private var borderColor: Color {
        guard isEnabled else { return FlintBrand.line }
        switch kind {
        case .primary:
            return FlintBrand.signal
        case .secondary:
            return FlintBrand.line
        }
    }
}

private struct PermissionStatusRow: View {
    let status: PermissionStatus
    let onResolve: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status.statusLine)
                    .font(FlintTypography.body(size: 14, weight: .semibold))
                Spacer()
                if status.isReady {
                    Text("Ready")
                        .font(FlintTypography.mono(size: 10, weight: .semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.green)
                } else {
                    Button(status.kind == .accessibility ? "Turn On in Settings" : "Open Settings", action: onResolve)
                        .buttonStyle(OnboardingActionButtonStyle(kind: .primary, compact: true))
                }
            }
            Text(status.explanation)
                .font(FlintTypography.body(size: 12))
                .foregroundStyle(FlintBrand.muted)
        }
        .padding(14)
        .background(FlintBrand.mist.opacity(0.48))
        .overlay {
            Rectangle()
                .stroke(status.isReady ? Color.green.opacity(0.35) : FlintBrand.line, lineWidth: 1)
        }
    }
}

private struct OnboardingFeaturePill: View {
    let icon: String
    let label: String

    var body: some View {
        Label(label, systemImage: icon)
            .font(FlintTypography.mono(size: 10, weight: .semibold))
            .textCase(.uppercase)
            .tracking(0.25)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .foregroundStyle(FlintBrand.ink)
            .background(FlintBrand.paper)
            .overlay {
                Rectangle()
                    .stroke(FlintBrand.line, lineWidth: 1)
            }
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
                .frame(width: 34, height: 34)
                .background(FlintBrand.paper, in: Circle())
                .overlay {
                    Circle()
                        .stroke(FlintBrand.signal, lineWidth: 1)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(FlintTypography.heading(size: 16, weight: .semibold))
                Text(detail)
                    .font(FlintTypography.body(size: 13))
                    .foregroundStyle(FlintBrand.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FlintBrand.mist.opacity(0.42))
        .overlay {
            Rectangle()
                .stroke(FlintBrand.line, lineWidth: 1)
        }
    }
}
