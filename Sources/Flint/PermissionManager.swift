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

struct PermissionManager {
    var microphoneAuthorizationStatus: () -> AVAuthorizationStatus = {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }
    var accessibilityTrusted: () -> Bool = {
        AXIsProcessTrusted()
    }
    var inputMonitoringTrusted: () -> Bool = {
        CGPreflightListenEventAccess()
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

    func requestAccessibilityPrompt() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    func requestInputMonitoringPrompt() {
        CGRequestListenEventAccess()
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
