import XCTest
@testable import Flint

final class LicenseActivationTests: XCTestCase {
    private var licenseManager: LicenseManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        licenseManager = LicenseManager(
            service: "com.flint.tests.activation.\(UUID().uuidString)",
            account: "local-activation"
        )
        try licenseManager.clear()
    }

    override func tearDownWithError() throws {
        try? licenseManager?.clear()
        licenseManager = nil
        try super.tearDownWithError()
    }

    func testEmptyLicenseKeyIsRejectedBeforeClientActivation() async throws {
        var clientCallCount = 0
        let service = LicenseActivationService(
            client: { _ in
                clientCallCount += 1
                return makeResponse()
            },
            licenseManager: licenseManager
        )

        await XCTAssertThrowsErrorAsync(try await service.activate(licenseKey: "  \n\t ")) { error in
            XCTAssertEqual(error as? LicenseActivationService.ActivationError, .emptyLicenseKey)
        }
        XCTAssertEqual(clientCallCount, 0)
        XCTAssertEqual(try licenseManager.load(), .inactive)
    }

    func testSuccessfulActivationStoresHashedLicenseRecord() async throws {
        let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let checkedAt = Date(timeIntervalSince1970: 1_700_003_600)
        let service = LicenseActivationService(
            client: { licenseKey in
                XCTAssertEqual(licenseKey, "FLINT-TRIMMED-KEY")
                return makeResponse(
                    activationID: "act_success",
                    status: .activated,
                    activatedAt: activatedAt,
                    checkedAt: checkedAt
                )
            },
            licenseManager: licenseManager
        )

        let record = try await service.activate(licenseKey: "  FLINT-TRIMMED-KEY  ")

        let expected = LicenseRecord(
            licenseKeyHash: LicenseManager.hashLicenseKey("FLINT-TRIMMED-KEY"),
            activationID: "act_success",
            status: .activated,
            activatedAt: activatedAt,
            lastCheckedAt: checkedAt
        )
        XCTAssertEqual(record, expected)
        XCTAssertEqual(try licenseManager.load(), expected)
        XCTAssertNotEqual(record.licenseKeyHash, "FLINT-TRIMMED-KEY")
    }

    func testOfflineValidActivationResponsePersistsOfflineValidRecord() async throws {
        let service = LicenseActivationService(
            client: { _ in makeResponse(status: .offlineValid) },
            licenseManager: licenseManager
        )

        let record = try await service.activate(licenseKey: "FLINT-OFFLINE")

        XCTAssertEqual(record.status, .offlineValid)
        XCTAssertEqual(try licenseManager.load(), record)
    }

    func testFailedActivationDoesNotOverwriteExistingLicense() async throws {
        try licenseManager.saveActivatedLicense(
            licenseKey: "FLINT-EXISTING",
            activationID: "act_existing",
            activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let existingRecord = try licenseManager.load()
        let service = LicenseActivationService(
            client: { _ in makeResponse(status: .revoked) },
            licenseManager: licenseManager
        )

        await XCTAssertThrowsErrorAsync(try await service.activate(licenseKey: "FLINT-NEW")) { error in
            XCTAssertEqual(error as? LicenseActivationService.ActivationError, .revokedLicense)
        }
        XCTAssertEqual(try licenseManager.load(), existingRecord)
    }

    func testActivationStatusErrorsAreDeterministic() async throws {
        try await assertActivationFailure(status: .inactive, expected: .invalidLicense)
        try await assertActivationFailure(status: .expired, expected: .expiredLicense)
        try await assertActivationFailure(status: .revoked, expected: .revokedLicense)
    }

    func testTransportFailureMapsToDeterministicError() async throws {
        struct NetworkError: LocalizedError {
            var errorDescription: String? { "Network unavailable." }
        }
        let service = LicenseActivationService(
            client: { _ in throw NetworkError() },
            licenseManager: licenseManager
        )

        await XCTAssertThrowsErrorAsync(try await service.activate(licenseKey: "FLINT-NETWORK")) { error in
            XCTAssertEqual(
                error as? LicenseActivationService.ActivationError,
                .transport("Network unavailable.")
            )
        }
        XCTAssertEqual(try licenseManager.load(), .inactive)
    }

    func testMissingActivationIDDoesNotPersistLicense() async throws {
        let service = LicenseActivationService(
            client: { _ in makeResponse(activationID: "  ") },
            licenseManager: licenseManager
        )

        await XCTAssertThrowsErrorAsync(try await service.activate(licenseKey: "FLINT-NO-ID")) { error in
            XCTAssertEqual(error as? LicenseActivationService.ActivationError, .missingActivationID)
        }
        XCTAssertEqual(try licenseManager.load(), .inactive)
    }

    private func assertActivationFailure(
        status: LicenseStatus,
        expected: LicenseActivationService.ActivationError
    ) async throws {
        let service = LicenseActivationService(
            client: { _ in makeResponse(status: status) },
            licenseManager: licenseManager
        )

        await XCTAssertThrowsErrorAsync(try await service.activate(licenseKey: "FLINT-FAIL")) { error in
            XCTAssertEqual(error as? LicenseActivationService.ActivationError, expected)
        }
        XCTAssertEqual(try licenseManager.load(), .inactive)
    }
}

private func makeResponse(
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

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ validation: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown.", file: file, line: line)
    } catch {
        validation(error)
    }
}
