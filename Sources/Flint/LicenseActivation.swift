import Foundation

struct LicenseActivationResponse: Equatable {
    let activationID: String
    let status: LicenseStatus
    let activatedAt: Date
    let checkedAt: Date
}

struct LicenseActivationService {
    enum ActivationError: LocalizedError, Equatable {
        case emptyLicenseKey
        case invalidLicense
        case expiredLicense
        case revokedLicense
        case inactiveResponse(LicenseStatus)
        case missingActivationID
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .emptyLicenseKey:
                return "Enter a license key."
            case .invalidLicense:
                return "That license key is not valid."
            case .expiredLicense:
                return "That license key has expired."
            case .revokedLicense:
                return "That license key has been revoked."
            case .inactiveResponse(let status):
                return "License activation returned inactive status \(status.rawValue)."
            case .missingActivationID:
                return "License activation did not return an activation ID."
            case .transport(let message):
                return message
            }
        }
    }

    var client: (String) async throws -> LicenseActivationResponse
    var licenseManager: LicenseManager

    @discardableResult
    func activate(licenseKey rawLicenseKey: String) async throws -> LicenseRecord {
        let licenseKey = rawLicenseKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !licenseKey.isEmpty else {
            throw ActivationError.emptyLicenseKey
        }

        let response: LicenseActivationResponse
        do {
            response = try await client(licenseKey)
        } catch let error as ActivationError {
            throw error
        } catch {
            throw ActivationError.transport(error.localizedDescription)
        }

        let record = try record(for: response, licenseKey: licenseKey)
        try licenseManager.save(record)
        return record
    }

    private func record(
        for response: LicenseActivationResponse,
        licenseKey: String
    ) throws -> LicenseRecord {
        guard !response.activationID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ActivationError.missingActivationID
        }

        switch response.status {
        case .activated, .offlineValid:
            return LicenseRecord(
                licenseKeyHash: LicenseManager.hashLicenseKey(licenseKey),
                activationID: response.activationID,
                status: response.status,
                activatedAt: response.activatedAt,
                lastCheckedAt: response.checkedAt
            )
        case .inactive:
            throw ActivationError.invalidLicense
        case .expired:
            throw ActivationError.expiredLicense
        case .revoked:
            throw ActivationError.revokedLicense
        }
    }
}
