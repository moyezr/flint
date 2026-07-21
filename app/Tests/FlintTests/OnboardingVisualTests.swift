import AppKit
import SwiftUI
import XCTest
@testable import Flint

@MainActor
final class OnboardingVisualTests: XCTestCase {
    func testWelcomeScreenRendersWithLandingDesignSystem() throws {
        let png = try render(
            step: .welcome,
            snapshot: PermissionSnapshot(statuses: [
                PermissionStatus(kind: .microphone, readiness: .ready),
                PermissionStatus(kind: .accessibility, readiness: .ready)
            ]),
            filename: "Flint-Onboarding-Welcome.png"
        )

        XCTAssertGreaterThan(png.count, 20_000)
    }

    func testPermissionScreenRendersWithoutClippingMissingActions() throws {
        let png = try render(
            step: .permissions,
            snapshot: PermissionSnapshot(statuses: [
                PermissionStatus(kind: .microphone, readiness: .ready),
                PermissionStatus(kind: .accessibility, readiness: .denied)
            ]),
            filename: "Flint-Onboarding-Permissions.png"
        )

        XCTAssertGreaterThan(png.count, 20_000)
    }

    private func render(
        step: OnboardingStep,
        snapshot: PermissionSnapshot,
        filename: String
    ) throws -> Data {
        let suiteName = "FlintTests.OnboardingVisual.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let flow = OnboardingFlow(
            store: AppSettingsStore(defaults: defaults),
            permissionSnapshotProvider: { snapshot },
            permissionPromptAction: {},
            modelInstalledProvider: { _ in true },
            modelDownloadAction: { _, _ in },
            initialStep: step
        )
        let modelManager = ModelManager(
            defaults: defaults,
            modelCacheRoot: FileManager.default.temporaryDirectory
                .appendingPathComponent("flint-onboarding-visual-models", isDirectory: true)
        )
        let view = OnboardingView(flow: flow, modelManager: modelManager, onTestDictation: {})
            .frame(width: 820, height: 610)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 820, height: 610)
        hostingView.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(filename)
        try png.write(to: outputURL, options: .atomic)

        XCTAssertGreaterThanOrEqual(bitmap.pixelsWide, 820)
        XCTAssertGreaterThanOrEqual(bitmap.pixelsHigh, 610)
        XCTAssertEqual(
            Double(bitmap.pixelsWide) / Double(bitmap.pixelsHigh),
            820.0 / 610.0,
            accuracy: 0.001
        )
        return png
    }
}
