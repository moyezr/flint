import ApplicationServices
import AVFoundation
import Foundation

enum PermissionKind: CaseIterable, Equatable {
    case microphone
    case accessibility
    case inputMonitoring

    var title: String {
        switch self {
        case .microphone:
            return "Microphone"
        case .accessibility:
            return "Accessibility"
        case .inputMonitoring:
            return "Input Monitoring"
        }
    }

    var explanation: String {
        switch self {
        case .microphone:
            return "Microphone lets Flint record your voice for local transcription."
        case .accessibility:
            return "Accessibility lets Flint insert text into the field you're typing in."
        case .inputMonitoring:
            return "Input Monitoring lets Flint detect your dictation shortcut."
        }
    }
}

enum PermissionReadiness: Equatable {
    case ready
    case notDetermined
    case denied
    case restricted
    case unavailable

    var isReady: Bool {
        self == .ready
    }
}

struct PermissionStatus: Equatable {
    let kind: PermissionKind
    let readiness: PermissionReadiness

    var isReady: Bool {
        readiness.isReady
    }

    var title: String {
        kind.title
    }

    var explanation: String {
        kind.explanation
    }

    var statusLine: String {
        switch readiness {
        case .ready:
            return "\(title): Ready"
        case .notDetermined:
            return "\(title): Not granted yet"
        case .denied:
            return "\(title): Needs permission"
        case .restricted:
            return "\(title): Restricted by macOS"
        case .unavailable:
            return "\(title): Unavailable"
        }
    }

    var failureMessage: String {
        switch kind {
        case .microphone:
            return "Microphone permission is required. Allow Flint in Privacy & Security."
        case .accessibility:
            return "Accessibility is required to insert text at the cursor. Allow Flint in Privacy & Security."
        case .inputMonitoring:
            return "Input Monitoring is required for the shortcut. Allow Flint in Privacy & Security."
        }
    }

    static func isPermissionFailureMessage(_ message: String) -> Bool {
        PermissionKind.allCases.contains { kind in
            PermissionStatus(kind: kind, readiness: .denied).failureMessage == message
        }
    }
}

struct PermissionSnapshot: Equatable {
    let statuses: [PermissionStatus]

    var missingStatuses: [PermissionStatus] {
        statuses.filter { !$0.isReady }
    }

    var missingCount: Int {
        missingStatuses.count
    }

    func status(for kind: PermissionKind) -> PermissionStatus {
        statuses.first { $0.kind == kind } ?? PermissionStatus(kind: kind, readiness: .unavailable)
    }
}

enum PermissionSettingsRoute {
    static func url(for kind: PermissionKind) -> URL? {
        let anchor: String
        switch kind {
        case .microphone:
            anchor = "Privacy_Microphone"
        case .accessibility:
            anchor = "Privacy_Accessibility"
        case .inputMonitoring:
            anchor = "Privacy_ListenEvent"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")
    }

    static func url(for snapshot: PermissionSnapshot) -> URL? {
        snapshot.missingStatuses.first.flatMap { url(for: $0.kind) }
    }
}

enum ShortcutMonitoringPermissionPolicy {
    static func shouldStart(for snapshot: PermissionSnapshot) -> Bool {
        snapshot.status(for: .inputMonitoring).isReady
    }
}

struct PermissionManager {
    var microphoneAuthorizationStatus: () -> AVAuthorizationStatus = {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }
    var requestMicrophoneAccess: () async -> Bool = {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }
    var accessibilityTrusted: () -> Bool = {
        AXIsProcessTrusted()
    }
    var requestAccessibilityAccess: () -> Void = {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
    var inputMonitoringTrusted: () -> Bool = {
        CGPreflightListenEventAccess()
    }
    var requestInputMonitoringAccess: () -> Void = {
        CGRequestListenEventAccess()
    }

    func snapshot() -> PermissionSnapshot {
        PermissionSnapshot(statuses: [
            microphoneStatus(),
            PermissionStatus(kind: .accessibility, readiness: accessibilityTrusted() ? .ready : .denied),
            PermissionStatus(kind: .inputMonitoring, readiness: inputMonitoringTrusted() ? .ready : .denied)
        ])
    }

    func microphoneStatus() -> PermissionStatus {
        PermissionStatus(kind: .microphone, readiness: Self.readiness(for: microphoneAuthorizationStatus()))
    }

    func requestMicrophonePermission() async {
        guard microphoneStatus().readiness == .notDetermined else {
            return
        }
        _ = await requestMicrophoneAccess()
    }

    func requestAccessibilityPermission() {
        requestAccessibilityAccess()
    }

    func requestInputMonitoringPermission() {
        requestInputMonitoringAccess()
    }

    func requestPermission(_ kind: PermissionKind) async {
        switch kind {
        case .microphone:
            await requestMicrophonePermission()
        case .accessibility:
            requestAccessibilityPermission()
        case .inputMonitoring:
            requestInputMonitoringPermission()
        }
    }

    func requestMissingPermissions() async {
        let currentSnapshot = snapshot()

        let microphone = currentSnapshot.status(for: .microphone)
        if !microphone.isReady {
            if microphone.readiness == .notDetermined {
                _ = await requestMicrophoneAccess()
            }
            return
        }
        if !currentSnapshot.status(for: .accessibility).isReady {
            requestAccessibilityAccess()
            return
        }
        if !currentSnapshot.status(for: .inputMonitoring).isReady {
            requestInputMonitoringAccess()
        }
    }

    static func readiness(for authorizationStatus: AVAuthorizationStatus) -> PermissionReadiness {
        switch authorizationStatus {
        case .authorized:
            return .ready
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unavailable
        }
    }
}
