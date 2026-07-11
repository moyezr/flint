import Security
import XCTest
@testable import Flint

final class LicenseManagerTests: XCTestCase {
    private var service: String!
    private var account: String!
    private var manager: LicenseManager!

    override func setUpWithError() throws {
        try super.setUpWithError()
        service = "com.flint.tests.license.\(UUID().uuidString)"
        account = "activation-\(UUID().uuidString)"
        manager = LicenseManager(service: service, account: account)
        try manager.clear()
    }

    override func tearDownWithError() throws {
        try? manager?.clear()
        manager = nil
        account = nil
        service = nil
        try super.tearDownWithError()
    }

    func testSaveLoadAndDeleteActivatedLicense() throws {
        let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let checkedAt = Date(timeIntervalSince1970: 1_700_003_600)

        try manager.saveActivatedLicense(
            licenseKey: "FLINT-TEST-KEY",
            activationID: "act_123",
            activatedAt: activatedAt,
            lastCheckedAt: checkedAt
        )

        XCTAssertEqual(try manager.load(), LicenseRecord(
            licenseKeyHash: LicenseManager.hashLicenseKey("FLINT-TEST-KEY"),
            activationID: "act_123",
            status: .activated,
            activatedAt: activatedAt,
            lastCheckedAt: checkedAt
        ))

        try manager.clear()

        XCTAssertEqual(try manager.load(), .inactive)
    }

    func testSaveLoadOfflineValidLicense() throws {
        let activatedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let checkedAt = Date(timeIntervalSince1970: 1_700_086_400)
        let hash = LicenseManager.hashLicenseKey("FLINT-OFFLINE-KEY")

        try manager.saveOfflineValidLicense(
            licenseKeyHash: hash,
            activationID: "act_offline",
            activatedAt: activatedAt,
            lastCheckedAt: checkedAt
        )

        XCTAssertEqual(try manager.load(), LicenseRecord(
            licenseKeyHash: hash,
            activationID: "act_offline",
            status: .offlineValid,
            activatedAt: activatedAt,
            lastCheckedAt: checkedAt
        ))
    }

    func testPlaintextLicenseKeyIsNotPersisted() throws {
        let licenseKey = "FLINT-PLAINTEXT-SHOULD-NOT-BE-STORED"

        try manager.saveActivatedLicense(
            licenseKey: licenseKey,
            activationID: "act_plaintext",
            activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        let storedData = try XCTUnwrap(readRawKeychainData())
        let storedString = String(decoding: storedData, as: UTF8.self)
        XCTAssertFalse(storedString.contains(licenseKey))
        XCTAssertTrue(storedString.contains(LicenseManager.hashLicenseKey(licenseKey)))
    }

    func testHashingIsStableAndDistinct() {
        let first = LicenseManager.hashLicenseKey("FLINT-STABLE-KEY")
        let second = LicenseManager.hashLicenseKey("FLINT-STABLE-KEY")
        let different = LicenseManager.hashLicenseKey("FLINT-DIFFERENT-KEY")

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 64)
        XCTAssertNotEqual(first, different)
    }

    func testMissingRecordLoadsInactiveAndClearIsIdempotent() throws {
        try manager.clear()

        XCTAssertEqual(try manager.load(), .inactive)
        XCTAssertNoThrow(try manager.clear())
    }

    func testCorruptRecordLoadsInactiveWithoutCrashing() throws {
        try writeRawKeychainData(Data("not-json".utf8))

        XCTAssertEqual(try manager.load(), .inactive)
    }

    func testInactivePersistedRecordLoadsInactive() throws {
        let inactiveRecord = LicenseRecord.inactive
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(inactiveRecord)
        try writeRawKeychainData(data)

        XCTAssertEqual(try manager.load(), .inactive)
    }

    func testPersistedActiveRecordWithoutRequiredIdentityLoadsInactive() throws {
        let incompleteRecord = LicenseRecord(
            licenseKeyHash: nil,
            activationID: "act_incomplete",
            status: .activated,
            activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(incompleteRecord)
        try writeRawKeychainData(data)

        XCTAssertEqual(try manager.load(), .inactive)
    }

    func testSaveRejectsActiveRecordWithoutRequiredIdentity() {
        let missingLicenseHash = LicenseRecord(
            licenseKeyHash: nil,
            activationID: "act_missing_hash",
            status: .activated,
            activatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastCheckedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )

        XCTAssertThrowsError(try manager.save(missingLicenseHash)) { error in
            XCTAssertEqual(error as? LicenseManager.LicenseManagerError, .missingActivationIdentity)
        }
    }

    func testKeychainReadFailureThrowsInsteadOfLoadingInactive() {
        let failingManager = LicenseManager(
            service: service,
            account: account,
            keychain: LicenseKeychainClient(
                copyMatching: { _, _ in errSecAuthFailed },
                update: { _, _ in errSecSuccess },
                add: { _, _ in errSecSuccess },
                delete: { _ in errSecSuccess }
            )
        )

        XCTAssertThrowsError(try failingManager.load()) { error in
            XCTAssertEqual(
                error as? LicenseManager.LicenseManagerError,
                .keychainFailure(operation: "read", status: errSecAuthFailed)
            )
        }
    }

    private func readRawKeychainData() throws -> Data? {
        var query = keychainQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw LicenseManager.LicenseManagerError.keychainFailure(operation: "test read", status: status)
        }
        return result as? Data
    }

    private func writeRawKeychainData(_ data: Data) throws {
        try? manager.clear()
        var query = keychainQuery()
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw LicenseManager.LicenseManagerError.keychainFailure(operation: "test add", status: status)
        }
    }

    private func keychainQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service!,
            kSecAttrAccount as String: account!
        ]
    }
}
