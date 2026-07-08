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
        let manager = PermissionManager(
            microphoneAuthorizationStatus: { .denied },
            accessibilityTrusted: { true },
            inputMonitoringTrusted: { false }
        )

        let snapshot = manager.snapshot()

        XCTAssertEqual(snapshot.missingCount, 2)
        XCTAssertEqual(snapshot.status(for: .microphone).readiness, .denied)
        XCTAssertEqual(snapshot.status(for: .accessibility).readiness, .ready)
        XCTAssertEqual(snapshot.status(for: .inputMonitoring).readiness, .denied)
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
