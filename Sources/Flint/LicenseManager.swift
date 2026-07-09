import CryptoKit
import Foundation
import Security

enum LicenseStatus: String, Codable, Equatable {
    case inactive
    case activated
    case offlineValid = "offline_valid"
    case expired
    case revoked
}

struct LicenseRecord: Codable, Equatable {
    var licenseKeyHash: String?
    var activationID: String?
    var status: LicenseStatus
    var activatedAt: Date?
    var lastCheckedAt: Date?

    static let inactive = LicenseRecord(
        licenseKeyHash: nil,
        activationID: nil,
        status: .inactive,
        activatedAt: nil,
        lastCheckedAt: nil
    )

    var isActive: Bool {
        status == .activated || status == .offlineValid
    }

    var hasActivationIdentity: Bool {
        hasNonEmptyValue(licenseKeyHash) && hasNonEmptyValue(activationID)
    }

    enum CodingKeys: String, CodingKey {
        case licenseKeyHash = "license_key_hash"
        case activationID = "activation_id"
        case status
        case activatedAt = "activated_at"
        case lastCheckedAt = "last_checked_at"
    }

    private func hasNonEmptyValue(_ value: String?) -> Bool {
        guard let value else {
            return false
        }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct LicenseManager {
    enum LicenseManagerError: LocalizedError, Equatable {
        case invalidPersistedStatus(LicenseStatus)
        case missingActivationIdentity
        case keychainFailure(operation: String, status: OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidPersistedStatus(let status):
                return "Cannot persist inactive license status \(status.rawValue)."
            case .missingActivationIdentity:
                return "Cannot persist an active license without a license hash and activation ID."
            case .keychainFailure(let operation, let status):
                return "Keychain \(operation) failed with status \(status)."
            }
        }
    }

    private let service: String
    private let account: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let keychain: LicenseKeychainClient

    init(
        service: String = "com.flint.license",
        account: String = "local-activation",
        keychain: LicenseKeychainClient = .live
    ) {
        self.service = service
        self.account = account
        self.keychain = keychain
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> LicenseRecord {
        guard let data = try readData(),
              let record = try? decoder.decode(LicenseRecord.self, from: data),
              record.isActive,
              record.hasActivationIdentity else {
            return .inactive
        }
        return record
    }

    func saveActivatedLicense(
        licenseKey: String,
        activationID: String,
        activatedAt: Date = Date(),
        lastCheckedAt: Date = Date()
    ) throws {
        try save(LicenseRecord(
            licenseKeyHash: Self.hashLicenseKey(licenseKey),
            activationID: activationID,
            status: .activated,
            activatedAt: activatedAt,
            lastCheckedAt: lastCheckedAt
        ))
    }

    func saveOfflineValidLicense(
        licenseKeyHash: String,
        activationID: String,
        activatedAt: Date,
        lastCheckedAt: Date
    ) throws {
        try save(LicenseRecord(
            licenseKeyHash: licenseKeyHash,
            activationID: activationID,
            status: .offlineValid,
            activatedAt: activatedAt,
            lastCheckedAt: lastCheckedAt
        ))
    }

    func save(_ record: LicenseRecord) throws {
        guard record.isActive else {
            throw LicenseManagerError.invalidPersistedStatus(record.status)
        }
        guard record.hasActivationIdentity else {
            throw LicenseManagerError.missingActivationIdentity
        }
        let data = try encoder.encode(record)
        try writeData(data)
    }

    func clear() throws {
        let status = keychain.delete(baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw LicenseManagerError.keychainFailure(operation: "delete", status: status)
        }
    }

    static func hashLicenseKey(_ licenseKey: String) -> String {
        let digest = SHA256.hash(data: Data(licenseKey.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func readData() throws -> Data? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = keychain.copyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw LicenseManagerError.keychainFailure(operation: "read", status: status)
        }
        return result as? Data
    }

    private func writeData(_ data: Data) throws {
        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]

        let updateStatus = keychain.update(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw LicenseManagerError.keychainFailure(operation: "update", status: updateStatus)
        }

        var addQuery = query
        attributes.forEach { addQuery[$0.key] = $0.value }
        let addStatus = keychain.add(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw LicenseManagerError.keychainFailure(operation: "add", status: addStatus)
        }
    }

    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

struct LicenseKeychainClient {
    let copyMatching: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    let update: (CFDictionary, CFDictionary) -> OSStatus
    let add: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus
    let delete: (CFDictionary) -> OSStatus

    static let live = LicenseKeychainClient(
        copyMatching: SecItemCopyMatching,
        update: SecItemUpdate,
        add: SecItemAdd,
        delete: SecItemDelete
    )
}
