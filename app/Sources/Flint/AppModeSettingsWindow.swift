import AppKit
import SwiftUI

@MainActor
final class AppModeSettingsWindowController {
    private let window: NSWindow
    private let model: AppModeSettingsModel

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        ruleStore: AppModeRuleStore = AppModeRuleStore(),
        onSettingsChanged: @escaping (AppSettings) -> Void = { _ in }
    ) {
        model = AppModeSettingsModel(
            settingsStore: settingsStore,
            ruleStore: ruleStore,
            onSettingsChanged: onSettingsChanged
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Flint App Modes"
        window.contentView = NSHostingView(rootView: AppModeSettingsView(model: model))
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
final class AppModeSettingsModel: ObservableObject {
    @Published private(set) var settings: AppSettings
    @Published private(set) var rules: [AppModeRule] = []
    @Published var newBundleID = ""
    @Published var newMode: CleanupMode = .message
    @Published private(set) var message = ""
    @Published private(set) var errorMessage = ""

    private let settingsStore: AppSettingsStore
    private let ruleStore: AppModeRuleStore
    private let onSettingsChanged: (AppSettings) -> Void

    init(
        settingsStore: AppSettingsStore = AppSettingsStore(),
        ruleStore: AppModeRuleStore = AppModeRuleStore(),
        onSettingsChanged: @escaping (AppSettings) -> Void = { _ in }
    ) {
        self.settingsStore = settingsStore
        self.ruleStore = ruleStore
        self.onSettingsChanged = onSettingsChanged
        settings = settingsStore.load()
        refresh()
    }

    func refresh() {
        settings = settingsStore.load()
        do {
            rules = try ruleStore.list()
            errorMessage = ""
        } catch {
            rules = []
            errorMessage = error.localizedDescription
        }
    }

    func setAppAwareModesEnabled(_ enabled: Bool) {
        settingsStore.saveAppAwareModesEnabled(enabled)
        settings = settingsStore.load()
        onSettingsChanged(settings)
        message = enabled ? "App-aware modes enabled." : "App-aware modes disabled."
        errorMessage = ""
    }

    func addRule() {
        do {
            _ = try ruleStore.create(NewAppModeRule(
                appBundleID: newBundleID,
                mode: newMode
            ))
            newBundleID = ""
            refresh()
            message = "App mode rule added."
        } catch {
            message = ""
            errorMessage = error.localizedDescription
        }
    }

    func setEnabled(_ enabled: Bool, for rule: AppModeRule) {
        update(rule: rule, changes: AppModeRuleChanges(enabled: enabled))
    }

    func setMode(_ mode: CleanupMode, for rule: AppModeRule) {
        update(rule: rule, changes: AppModeRuleChanges(mode: mode))
    }

    func delete(_ rule: AppModeRule) {
        do {
            try ruleStore.delete(id: rule.id)
            refresh()
            message = "App mode rule deleted."
        } catch {
            message = ""
            errorMessage = error.localizedDescription
        }
    }

    private func update(rule: AppModeRule, changes: AppModeRuleChanges) {
        do {
            _ = try ruleStore.update(id: rule.id, changes: changes)
            refresh()
            message = "App mode rule updated."
        } catch {
            message = ""
            errorMessage = error.localizedDescription
        }
    }
}

private struct AppModeSettingsView: View {
    @ObservedObject var model: AppModeSettingsModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("App Modes")
                        .font(.system(size: 28, weight: .semibold))
                    Text("Optionally use a cleanup mode for a specific app. Your manual mode remains the fallback.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Toggle("Enable app-aware modes", isOn: Binding(
                        get: { model.settings.appAwareModesEnabled },
                        set: { model.setAppAwareModesEnabled($0) }
                    ))
                    .toggleStyle(.checkbox)
                    Text("Manual default: \(model.settings.cleanupMode.displayName)")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Rules")
                        .font(.system(size: 16, weight: .semibold))

                    if model.rules.isEmpty {
                        Text("No app-specific rules configured.")
                            .foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(model.rules) { rule in
                                AppModeRuleRow(
                                    rule: rule,
                                    onEnabledChanged: { model.setEnabled($0, for: rule) },
                                    onModeChanged: { model.setMode($0, for: rule) },
                                    onDelete: { model.delete(rule) }
                                )
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Add Rule")
                        .font(.system(size: 16, weight: .semibold))
                    TextField("App bundle ID, for example com.tinyspeck.slackmacgap", text: $model.newBundleID)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Picker("Mode", selection: $model.newMode) {
                            ForEach(CleanupMode.allCases, id: \.self) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .frame(width: 180)
                        Button("Add Rule") {
                            model.addRule()
                        }
                        .buttonStyle(.borderedProminent)
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
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minWidth: 680, minHeight: 560)
    }
}

private struct AppModeRuleRow: View {
    let rule: AppModeRule
    let onEnabledChanged: (Bool) -> Void
    let onModeChanged: (CleanupMode) -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { rule.enabled }, set: onEnabledChanged))
                .toggleStyle(.checkbox)
                .labelsHidden()
            VStack(alignment: .leading, spacing: 4) {
                Text(rule.appBundleID ?? rule.urlPattern ?? "Unknown matcher")
                    .font(.headline)
                if rule.urlPattern != nil && rule.appBundleID == nil {
                    Text("URL matching is not available yet.")
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Picker("Mode", selection: Binding(get: { rule.mode }, set: onModeChanged)) {
                ForEach(CleanupMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: 130)
            Button("Delete", role: .destructive, action: onDelete)
        }
        .padding(12)
        .overlay(
            Rectangle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }
}
