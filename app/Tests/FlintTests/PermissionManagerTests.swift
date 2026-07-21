import AVFoundation
import XCTest
@testable import Flint

final class PermissionManagerTests: XCTestCase {
    func testMicrophoneAuthorizationMapsToReadiness() {
        XCTAssertEqual(PermissionManager.readiness(for: .authorized), .ready)
        XCTAssertEqual(PermissionManager.readiness(for: .notDetermined), .notDetermined)
        XCTAssertEqual(PermissionManager.readiness(for: .denied), .denied)
        XCTAssertEqual(PermissionManager.readiness(for: .restricted), .restricted)
    }

    func testSnapshotUsesInjectedProvidersWithoutRequestingPermissions() {
        var microphoneRequestCount = 0
        var accessibilityRequestCount = 0
        var inputMonitoringRequestCount = 0
        let manager = PermissionManager(
            microphoneAuthorizationStatus: { .denied },
            requestMicrophoneAccess: {
                microphoneRequestCount += 1
                return false
            },
            accessibilityTrusted: { true },
            requestAccessibilityAccess: { accessibilityRequestCount += 1 },
            inputMonitoringTrusted: { false },
            requestInputMonitoringAccess: { inputMonitoringRequestCount += 1 }
        )

        let snapshot = manager.snapshot()

        XCTAssertEqual(snapshot.missingCount, 2)
        XCTAssertEqual(snapshot.status(for: .microphone).readiness, .denied)
        XCTAssertEqual(snapshot.status(for: .accessibility).readiness, .ready)
        XCTAssertEqual(snapshot.status(for: .inputMonitoring).readiness, .denied)
        XCTAssertEqual(microphoneRequestCount, 0)
        XCTAssertEqual(accessibilityRequestCount, 0)
        XCTAssertEqual(inputMonitoringRequestCount, 0)
    }

    func testMicrophoneRequestOnlyPromptsWhenNotDetermined() async {
        var notDeterminedRequestCount = 0
        let notDeterminedManager = PermissionManager(
            microphoneAuthorizationStatus: { .notDetermined },
            requestMicrophoneAccess: {
                notDeterminedRequestCount += 1
                return true
            }
        )

        await notDeterminedManager.requestMicrophonePermission()

        XCTAssertEqual(notDeterminedRequestCount, 1)

        for status in [AVAuthorizationStatus.authorized, .denied, .restricted] {
            var requestCount = 0
            let manager = PermissionManager(
                microphoneAuthorizationStatus: { status },
                requestMicrophoneAccess: {
                    requestCount += 1
                    return false
                }
            )

            await manager.requestMicrophonePermission()

            XCTAssertEqual(requestCount, 0, "Unexpected microphone prompt for \(status)")
        }
    }

    func testAccessibilityAndInputMonitoringExplicitRequestsUseInjectedClosures() {
        var accessibilityRequestCount = 0
        var inputMonitoringRequestCount = 0
        let manager = PermissionManager(
            requestAccessibilityAccess: { accessibilityRequestCount += 1 },
            requestInputMonitoringAccess: { inputMonitoringRequestCount += 1 }
        )

        manager.requestAccessibilityPermission()
        manager.requestInputMonitoringPermission()

        XCTAssertEqual(accessibilityRequestCount, 1)
        XCTAssertEqual(inputMonitoringRequestCount, 1)
    }

    func testRequestMissingPermissionsRequestsOneSystemPermissionPerPass() async {
        var microphoneRequestCount = 0
        var accessibilityRequestCount = 0
        var inputMonitoringRequestCount = 0
        var microphoneStatus = AVAuthorizationStatus.notDetermined
        let manager = PermissionManager(
            microphoneAuthorizationStatus: { microphoneStatus },
            requestMicrophoneAccess: {
                microphoneRequestCount += 1
                microphoneStatus = .authorized
                return true
            },
            accessibilityTrusted: { true },
            requestAccessibilityAccess: { accessibilityRequestCount += 1 },
            inputMonitoringTrusted: { false },
            requestInputMonitoringAccess: { inputMonitoringRequestCount += 1 }
        )

        await manager.requestMissingPermissions()

        XCTAssertEqual(microphoneRequestCount, 1)
        XCTAssertEqual(accessibilityRequestCount, 0)
        XCTAssertEqual(inputMonitoringRequestCount, 0)

        await manager.requestMissingPermissions()

        XCTAssertEqual(inputMonitoringRequestCount, 1)
    }

    func testAccessibilityRequestIsNotOverlappedByInputMonitoringRequest() async {
        var accessibilityRequestCount = 0
        var inputMonitoringRequestCount = 0
        let manager = PermissionManager(
            microphoneAuthorizationStatus: { .authorized },
            accessibilityTrusted: { false },
            requestAccessibilityAccess: { accessibilityRequestCount += 1 },
            inputMonitoringTrusted: { false },
            requestInputMonitoringAccess: { inputMonitoringRequestCount += 1 }
        )

        await manager.requestMissingPermissions()

        XCTAssertEqual(accessibilityRequestCount, 1)
        XCTAssertEqual(inputMonitoringRequestCount, 0)
    }

    func testPermissionSettingsRouteOpensFirstMissingPermission() {
        let microphoneURL = PermissionSettingsRoute.url(for: PermissionSnapshot(statuses: [
            PermissionStatus(kind: .microphone, readiness: .denied),
            PermissionStatus(kind: .accessibility, readiness: .denied),
            PermissionStatus(kind: .inputMonitoring, readiness: .denied)
        ]))
        let accessibilityURL = PermissionSettingsRoute.url(for: PermissionSnapshot(statuses: [
            PermissionStatus(kind: .microphone, readiness: .ready),
            PermissionStatus(kind: .accessibility, readiness: .denied),
            PermissionStatus(kind: .inputMonitoring, readiness: .denied)
        ]))
        let inputMonitoringURL = PermissionSettingsRoute.url(for: PermissionSnapshot(statuses: [
            PermissionStatus(kind: .microphone, readiness: .ready),
            PermissionStatus(kind: .accessibility, readiness: .ready),
            PermissionStatus(kind: .inputMonitoring, readiness: .denied)
        ]))

        XCTAssertTrue(microphoneURL?.absoluteString.hasSuffix("Privacy_Microphone") == true)
        XCTAssertTrue(accessibilityURL?.absoluteString.hasSuffix("Privacy_Accessibility") == true)
        XCTAssertTrue(inputMonitoringURL?.absoluteString.hasSuffix("Privacy_ListenEvent") == true)
    }

    func testRequestMissingPermissionsDoesNotReRequestDeniedOrRestrictedMicrophone() async {
        for status in [AVAuthorizationStatus.denied, .restricted] {
            var microphoneRequestCount = 0
            var accessibilityRequestCount = 0
            var inputMonitoringRequestCount = 0
            let manager = PermissionManager(
                microphoneAuthorizationStatus: { status },
                requestMicrophoneAccess: {
                    microphoneRequestCount += 1
                    return false
                },
                accessibilityTrusted: { false },
                requestAccessibilityAccess: { accessibilityRequestCount += 1 },
                inputMonitoringTrusted: { false },
                requestInputMonitoringAccess: { inputMonitoringRequestCount += 1 }
            )

            await manager.requestMissingPermissions()

            XCTAssertEqual(microphoneRequestCount, 0, "Unexpected microphone prompt for \(status)")
            XCTAssertEqual(accessibilityRequestCount, 0, "Later permission request overlapped \(status)")
            XCTAssertEqual(inputMonitoringRequestCount, 0, "Later permission request overlapped \(status)")
        }
    }

    func testStatusMessagesAreShortAndActionable() {
        let accessibility = PermissionStatus(kind: .accessibility, readiness: .denied)
        let inputMonitoring = PermissionStatus(kind: .inputMonitoring, readiness: .denied)
        let microphone = PermissionStatus(kind: .microphone, readiness: .denied)

        XCTAssertEqual(accessibility.explanation, "Accessibility lets Flint insert text into the field you're typing in.")
        XCTAssertEqual(inputMonitoring.explanation, "Input Monitoring lets Flint detect your dictation shortcut.")
        XCTAssertEqual(microphone.explanation, "Microphone lets Flint record your voice for local transcription.")
        XCTAssertTrue(accessibility.failureMessage.contains("Allow Flint in Privacy & Security"))
        XCTAssertTrue(inputMonitoring.failureMessage.contains("shortcut"))
        XCTAssertTrue(microphone.failureMessage.contains("Microphone permission is required"))
    }
}
