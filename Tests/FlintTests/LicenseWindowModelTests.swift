import Foundation
import Security
import XCTest
@testable import Flint

@MainActor
final class LicenseWindowModelTests: XCTestCase {
    private var keychain: InMemoryLicenseKeychain!
    private var licenseManager: LicenseManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        keychain = InMemoryLicenseKeychain()
        licenseManager = LicenseManager(
            service: "com.flint.tests.license-window.\(UUID().uuidString)",
            account: "local-activation",
            keychain: keychain.client
        )
    }

    override func tearDownWithError() throws {
        licenseManager = nil
        keychain = nil
        try super.tearDownWithError()
    }

    func testInactiveLicenseStateLoads() {
        let model = LicenseWindowModel(licenseManager: licenseManager)

        XCTAssertEqual(model.statusTitle, "Inactive")
        XCTAssertEqual(model.statusDetail, "No license activation is stored.")
        XCTAssertEqual(model.errorMessage, "")
    }

    func testActivatedLicenseLoadsWithoutPlaintextKeyExposure() throws {
        let licenseKey = "FLINT-SECRET-KEY"
        try licenseManager.saveActivatedLicense(
            licenseKey: licenseKey,
            activationID: "act_existing",
            activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let model = LicenseWindowModel(licenseManager: licenseManager)

        XCTAssertEqual(model.statusTitle, "Activated")
        XCTAssertTrue(model.statusDetail.contains("Activation ID: act_existing"))
        XCTAssertTrue(model.statusDetail.contains("License hash:"))
        XCTAssertFalse(model.statusDetail.contains(licenseKey))
    }

    func testOfflineValidLicenseLoads() throws {
        try licenseManager.saveOfflineValidLicense(
            licenseKeyHash: LicenseManager.hashLicenseKey("FLINT-OFFLINE-KEY"),
            activationID: "act_offline",
            activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )

        let model = LicenseWindowModel(licenseManager: licenseManager)

        XCTAssertEqual(model.statusTitle, "Offline Valid")
        XCTAssertTrue(model.statusDetail.contains("Activation ID: act_offline"))
    }

    func testClearActivationClearsManagerAndRefreshesState() throws {
        try licenseManager.saveActivatedLicense(
            licenseKey: "FLINT-CLEAR-KEY",
            activationID: "act_clear"
        )
        let model = LicenseWindowModel(licenseManager: licenseManager)

        model.clearActivation()

        XCTAssertEqual(try licenseManager.load(), .inactive)
        XCTAssertEqual(model.statusTitle, "Inactive")
        XCTAssertEqual(model.message, "Activation cleared.")
        XCTAssertEqual(model.errorMessage, "")
    }

    func testEmptyKeyIsRejectedBeforeActivationCall() async throws {
        var clientCallCount = 0
        let model = LicenseWindowModel(
            licenseManager: licenseManager,
            activationClient: { _ in
                clientCallCount += 1
                return makeLicenseWindowResponse()
            }
        )
        model.licenseKey = " \n\t "

        await model.activate()

        XCTAssertEqual(clientCallCount, 0)
        XCTAssertEqual(model.errorMessage, "Enter a license key.")
        XCTAssertEqual(model.statusTitle, "Inactive")
        XCTAssertEqual(try licenseManager.load(), .inactive)
    }

    func testSuccessfulActivationStoresHashedKeyClearsEntryAndRefreshesState() async throws {
        let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let checkedAt = Date(timeIntervalSince1970: 1_700_000_100)
        let model = LicenseWindowModel(
            licenseManager: licenseManager,
            activationClient: { licenseKey in
                XCTAssertEqual(licenseKey, "FLINT-SUCCESS-KEY")
                return makeLicenseWindowResponse(
                    activationID: "act_success",
                    status: .activated,
                    activatedAt: activatedAt,
                    checkedAt: checkedAt
                )
            }
        )
        model.licenseKey = "  FLINT-SUCCESS-KEY  "

        await model.activate()

        let stored = try licenseManager.load()
        XCTAssertEqual(stored, LicenseRecord(
            licenseKeyHash: LicenseManager.hashLicenseKey("FLINT-SUCCESS-KEY"),
            activationID: "act_success",
            status: .activated,
            activatedAt: activatedAt,
            lastCheckedAt: checkedAt
        ))
        XCTAssertEqual(model.licenseKey, "")
        XCTAssertEqual(model.statusTitle, "Activated")
        XCTAssertEqual(model.message, "License activated.")
        XCTAssertEqual(model.errorMessage, "")
        XCTAssertFalse(model.statusDetail.contains("FLINT-SUCCESS-KEY"))
    }

    func testInvalidRevokedAndExpiredActivationFailuresDoNotStoreLicense() async throws {
        try await assertActivationFailure(status: .inactive, expectedMessage: "That license key is not valid.")
        try await assertActivationFailure(status: .revoked, expectedMessage: "That license key has been revoked.")
        try await assertActivationFailure(status: .expired, expectedMessage: "That license key has expired.")
    }

    func testFailedActivationDoesNotOverwriteExistingValidRecord() async throws {
        try licenseManager.saveActivatedLicense(
            licenseKey: "FLINT-EXISTING-KEY",
            activationID: "act_existing",
            activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let existingRecord = try licenseManager.load()
        let model = LicenseWindowModel(
            licenseManager: licenseManager,
            activationClient: { _ in makeLicenseWindowResponse(status: .revoked) }
        )
        model.licenseKey = "FLINT-NEW-KEY"

        await model.activate()

        XCTAssertEqual(try licenseManager.load(), existingRecord)
        XCTAssertEqual(model.statusTitle, "Activated")
        XCTAssertEqual(model.errorMessage, "That license key has been revoked.")
    }

    func testDefaultActivationClientFailsAsNotConfigured() async throws {
        let model = LicenseWindowModel(licenseManager: licenseManager)
        model.licenseKey = "FLINT-LIVE-KEY"

        await model.activate()

        XCTAssertEqual(model.errorMessage, LicenseActivationService.notConfiguredMessage)
        XCTAssertEqual(try licenseManager.load(), .inactive)
        XCTAssertEqual(model.statusTitle, "Inactive")
    }

    private func assertActivationFailure(
        status: LicenseStatus,
        expectedMessage: String
    ) async throws {
        keychain.removeAll()
        let model = LicenseWindowModel(
            licenseManager: licenseManager,
            activationClient: { _ in makeLicenseWindowResponse(status: status) }
        )
        model.licenseKey = "FLINT-FAIL-KEY"

        await model.activate()

        XCTAssertEqual(model.errorMessage, expectedMessage)
        XCTAssertEqual(model.statusTitle, "Inactive")
        XCTAssertEqual(try licenseManager.load(), .inactive)
    }
}

private final class InMemoryLicenseKeychain {
    private var data: Data?

    var client: LicenseKeychainClient {
        LicenseKeychainClient(
            copyMatching: { [weak self] _, result in
                guard let self, let data = self.data else {
                    return errSecItemNotFound
                }
                result?.pointee = data as CFData
                return errSecSuccess
            },
            update: { [weak self] _, attributes in
                guard let self else {
                    return errSecItemNotFound
                }
                guard self.data != nil else {
                    return errSecItemNotFound
                }
                guard let attributes = attributes as? [String: Any],
                      let data = attributes[kSecValueData as String] as? Data else {
                    return errSecParam
                }
                self.data = data
                return errSecSuccess
            },
            add: { [weak self] query, _ in
                guard let self else {
                    return errSecItemNotFound
                }
                guard let query = query as? [String: Any],
                      let data = query[kSecValueData as String] as? Data else {
                    return errSecParam
                }
                self.data = data
                return errSecSuccess
            },
            delete: { [weak self] _ in
                self?.data = nil
                return errSecSuccess
            }
        )
    }

    func removeAll() {
        data = nil
    }
}

private func makeLicenseWindowResponse(
    activationID: String = "act_test",
    status: LicenseStatus = .activated,
    activatedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
    checkedAt: Date = Date(timeIntervalSince1970: 1_700_000_100)
) -> LicenseActivationResponse {
    LicenseActivationResponse(
        activationID: activationID,
        status: status,
        activatedAt: activatedAt,
        checkedAt: checkedAt
    )
}
