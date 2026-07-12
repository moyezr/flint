import CryptoKit
import Foundation
import Security

enum FlintLicenseConfiguration {
    static let apiBaseURL = URL(string: "https://flint.moyezrabbani.dev/api/licenses")!
    static let appBundleID = "com.moyezrabbani.Flint"
    static let certificatePublicKeyBase64URL = "ZKxbV7ikLt54o5zP6cjhpBotJjTWxXhWxCvBK9WRZKA"

    static var enforcementEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "FlintLicenseEnforcement") as? Bool) ?? false
    }
}

struct LicenseDeviceIdentity {
    private let privateKey: Curve25519.Signing.PrivateKey

    init(rawRepresentation: Data) throws {
        privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawRepresentation)
    }

    init() {
        privateKey = Curve25519.Signing.PrivateKey()
    }

    var publicKeyBase64URL: String {
        privateKey.publicKey.rawRepresentation.base64URLEncodedString()
    }

    var publicKeyHash: String {
        SHA256.hash(data: privateKey.publicKey.rawRepresentation).hexString
    }

    func signature(for message: String) throws -> String {
        try privateKey.signature(for: Data(message.utf8)).base64URLEncodedString()
    }

    var rawRepresentation: Data {
        privateKey.rawRepresentation
    }
}

struct LicenseDeviceIdentityStore {
    enum StoreError: LocalizedError {
        case keychain(OSStatus)

        var errorDescription: String? {
            "The device license key could not be accessed."
        }
    }

    private let service = "com.moyezrabbani.Flint.license-device"
    private let account = "ed25519-device-key-v1"

    func loadOrCreate() throws -> LicenseDeviceIdentity {
        if let existing = try load() {
            return existing
        }
        let identity = LicenseDeviceIdentity()
        let addStatus = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: identity.rawRepresentation
        ] as CFDictionary, nil)
        if addStatus == errSecSuccess {
            return identity
        }
        if addStatus == errSecDuplicateItem, let stored = try load() {
            return stored
        }
        throw StoreError.keychain(addStatus)
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }

    private func load() throws -> LicenseDeviceIdentity? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw StoreError.keychain(status)
        }
        return try LicenseDeviceIdentity(rawRepresentation: data)
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}

struct LicenseLease: Codable, Equatable {
    let activationID: String
    let certificate: String
    let expiresAt: Date
    var lastLocalVerificationAt: Date?
    var lastServerValidationAt: Date?
}

struct LicenseLeaseStore {
    enum StoreError: LocalizedError {
        case keychain(OSStatus)
        case invalidStoredLease

        var errorDescription: String? {
            switch self {
            case .keychain:
                return "The license lease could not be accessed."
            case .invalidStoredLease:
                return "The stored license lease is invalid. Activate Flint again."
            }
        }
    }

    private let service = "com.moyezrabbani.Flint.license-lease"
    private let account = "offline-certificate-v1"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load() throws -> LicenseLease? {
        var query = baseQuery
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw StoreError.keychain(status)
        }
        guard let lease = try? decoder.decode(LicenseLease.self, from: data) else {
            throw StoreError.invalidStoredLease
        }
        return lease
    }

    func save(_ lease: LicenseLease) throws {
        let data = try encoder.encode(lease)
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw StoreError.keychain(updateStatus)
        }
        let addStatus = SecItemAdd([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data
        ] as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw StoreError.keychain(addStatus)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }

    private var baseQuery: [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
    }
}

struct LicenseCertificatePayload: Codable, Equatable {
    let version: Int
    let licenseID: String
    let activationID: String
    let productID: String
    let appBundleID: String
    let deviceKeyHash: String
    let issuedAt: Date
    let expiresAt: Date
}

struct LicenseCertificateVerifier {
    enum VerificationError: LocalizedError, Equatable {
        case malformedCertificate
        case invalidSignature
        case wrongAppBundle
        case wrongDevice
        case expired

        var errorDescription: String? {
            switch self {
            case .malformedCertificate: return "The license certificate is malformed."
            case .invalidSignature: return "The license certificate signature is invalid."
            case .wrongAppBundle: return "The license certificate is for a different Flint build."
            case .wrongDevice: return "The license certificate belongs to a different Mac."
            case .expired: return "The license certificate has expired."
            }
        }
    }

    let publicKey: Curve25519.Signing.PublicKey
    let appBundleID: String
    let now: () -> Date

    init(
        publicKeyBase64URL: String = FlintLicenseConfiguration.certificatePublicKeyBase64URL,
        appBundleID: String = FlintLicenseConfiguration.appBundleID,
        now: @escaping () -> Date = Date.init
    ) throws {
        guard let publicKeyData = Data(base64URLEncoded: publicKeyBase64URL) else {
            throw VerificationError.malformedCertificate
        }
        publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: publicKeyData)
        self.appBundleID = appBundleID
        self.now = now
    }

    func verify(certificate: String, deviceIdentity: LicenseDeviceIdentity) throws -> LicenseCertificatePayload {
        let parts = certificate.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let payloadData = Data(base64URLEncoded: String(parts[0])),
              let signature = Data(base64URLEncoded: String(parts[1])) else {
            throw VerificationError.malformedCertificate
        }
        guard publicKey.isValidSignature(signature, for: Data(parts[0].utf8)) else {
            throw VerificationError.invalidSignature
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date.")
            }
            return date
        }
        guard let payload = try? decoder.decode(LicenseCertificatePayload.self, from: payloadData) else {
            throw VerificationError.malformedCertificate
        }
        guard payload.version == 1, payload.appBundleID == appBundleID else {
            throw VerificationError.wrongAppBundle
        }
        guard payload.deviceKeyHash == deviceIdentity.publicKeyHash else {
            throw VerificationError.wrongDevice
        }
        guard payload.expiresAt > now() else {
            throw VerificationError.expired
        }
        return payload
    }
}

private extension Data {
    init?(base64URLEncoded value: String) {
        var base64 = value.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(base64Encoded: base64)
    }

    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

struct LicenseAPIClient {
    enum APIError: LocalizedError {
        case invalidResponse
        case server(String)
        case transferPending

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Flint received an invalid license response."
            case .server(let message): return message
            case .transferPending: return "Confirm the device transfer email before activating Flint on this Mac."
            }
        }
    }

    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = FlintLicenseConfiguration.apiBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func activate(licenseKey: String, deviceName: String) async throws -> LicenseLease {
        let identity = try LicenseDeviceIdentityStore().loadOrCreate()
        let challenge = try await requestChallenge(identity: identity, purpose: "activate")
        let response: ActivationResponse = try await request(
            path: "activate",
            body: ActivationRequest(licenseKey: licenseKey, deviceName: deviceName, proof: try proof(for: challenge, identity: identity))
        )
        guard response.kind == "activated", let activationID = response.activationID,
              let certificate = response.certificate, let expiresAt = response.expiresAt else {
            if response.kind == "transfer_pending" { throw APIError.transferPending }
            throw APIError.invalidResponse
        }
        return try verifiedLease(activationID: activationID, certificate: certificate, expiresAt: expiresAt, identity: identity)
    }

    func validate(lease: LicenseLease) async throws -> LicenseLease {
        let identity = try LicenseDeviceIdentityStore().loadOrCreate()
        let challenge = try await requestChallenge(identity: identity, purpose: "validate")
        let response: ActivationResponse = try await request(
            path: "validate",
            body: ValidationRequest(activationID: lease.activationID, proof: try proof(for: challenge, identity: identity))
        )
        guard response.kind == "activated", let activationID = response.activationID,
              let certificate = response.certificate, let expiresAt = response.expiresAt else {
            throw APIError.invalidResponse
        }
        return try verifiedLease(activationID: activationID, certificate: certificate, expiresAt: expiresAt, identity: identity)
    }

    func deactivate(lease: LicenseLease) async throws {
        let identity = try LicenseDeviceIdentityStore().loadOrCreate()
        let challenge = try await requestChallenge(identity: identity, purpose: "deactivate")
        let _: EmptyResponse = try await request(
            path: "deactivate",
            body: ValidationRequest(activationID: lease.activationID, proof: try proof(for: challenge, identity: identity))
        )
    }

    private func requestChallenge(identity: LicenseDeviceIdentity, purpose: String) async throws -> ChallengeResponse {
        try await request(path: "challenges", body: ChallengeRequest(devicePublicKey: identity.publicKeyBase64URL, purpose: purpose))
    }

    private func proof(for challenge: ChallengeResponse, identity: LicenseDeviceIdentity) throws -> DeviceProof {
        DeviceProof(
            challengeID: challenge.challengeID,
            challengeNonce: challenge.nonce,
            challengeSignature: try identity.signature(for: challenge.message),
            devicePublicKey: identity.publicKeyBase64URL
        )
    }

    private func verifiedLease(
        activationID: String,
        certificate: String,
        expiresAt: Date,
        identity: LicenseDeviceIdentity
    ) throws -> LicenseLease {
        let payload = try LicenseCertificateVerifier().verify(certificate: certificate, deviceIdentity: identity)
        guard payload.activationID == activationID,
              abs(payload.expiresAt.timeIntervalSince(expiresAt)) < 1 else {
            throw APIError.invalidResponse
        }
        return LicenseLease(
            activationID: activationID,
            certificate: certificate,
            expiresAt: expiresAt,
            lastLocalVerificationAt: Date(),
            lastServerValidationAt: Date()
        )
    }

    private func request<RequestBody: Encodable, ResponseBody: Decodable>(path: String, body: RequestBody) async throws -> ResponseBody {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 204, ResponseBody.self == EmptyResponse.self {
            return EmptyResponse() as! ResponseBody
        }
        guard (200..<300).contains(http.statusCode) else {
            let error = try? JSONDecoder().decode(ServerErrorResponse.self, from: data)
            throw APIError.server(error?.error.message ?? "The licensing service rejected this request.")
        }
        do {
            return try licenseJSONDecoder.decode(ResponseBody.self, from: data)
        } catch {
            throw APIError.invalidResponse
        }
    }
}

@MainActor
final class LicenseAuthorizationController {
    private enum Decision {
        case allowed
        case blocked(String)
    }

    private let leaseStore = LicenseLeaseStore()
    private let identityStore = LicenseDeviceIdentityStore()
    private let client = LicenseAPIClient()
    private var decision: Decision = .allowed
    private var timer: Timer?

    var blockingMessage: String? {
        guard FlintLicenseConfiguration.enforcementEnabled else { return nil }
        if case .blocked(let message) = decision { return message }
        return nil
    }

    func start() {
        refreshLocalAuthorization()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 24 * 60 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshLocalAuthorization() }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func refreshLocalAuthorization() {
        guard FlintLicenseConfiguration.enforcementEnabled else {
            decision = .allowed
            return
        }
        do {
            guard var lease = try leaseStore.load() else {
                decision = .blocked("Activate Flint before dictation.")
                return
            }
            let identity = try identityStore.loadOrCreate()
            _ = try LicenseCertificateVerifier().verify(certificate: lease.certificate, deviceIdentity: identity)
            decision = .allowed
            if lease.lastLocalVerificationAt?.addingTimeInterval(24 * 60 * 60) ?? .distantPast < Date() {
                lease.lastLocalVerificationAt = Date()
                try leaseStore.save(lease)
            }
            refreshFromServerIfDue(lease)
        } catch {
            decision = .blocked("Activate Flint before dictation.")
        }
    }

    private func refreshFromServerIfDue(_ lease: LicenseLease) {
        let nextValidation = lease.lastServerValidationAt?.addingTimeInterval(30 * 24 * 60 * 60) ?? .distantPast
        guard nextValidation < Date() else { return }
        Task { [weak self] in
            do {
                guard let self else { return }
                let renewed = try await self.client.validate(lease: lease)
                try self.leaseStore.save(renewed)
            } catch {
                // The verified local certificate remains valid until its expiry.
            }
        }
    }
}

struct ProductionLicenseActivationClient {
    func activate(licenseKey: String) async throws -> LicenseActivationResponse {
        let lease = try await LicenseAPIClient().activate(
            licenseKey: licenseKey,
            deviceName: Host.current().localizedName ?? "This Mac"
        )
        try LicenseLeaseStore().save(lease)
        return LicenseActivationResponse(
            activationID: lease.activationID,
            status: .activated,
            activatedAt: Date(),
            checkedAt: Date()
        )
    }

    func deactivateCurrentDevice() async throws {
        let leaseStore = LicenseLeaseStore()
        guard let lease = try leaseStore.load() else { return }
        try await LicenseAPIClient().deactivate(lease: lease)
        try leaseStore.clear()
    }
}

private struct ChallengeRequest: Encodable {
    let devicePublicKey: String
    let purpose: String
}

private struct DeviceProof: Encodable {
    let challengeID: String
    let challengeNonce: String
    let challengeSignature: String
    let devicePublicKey: String
}

private struct ActivationRequest: Encodable {
    let licenseKey: String
    let deviceName: String
    let challengeID: String
    let challengeNonce: String
    let challengeSignature: String
    let devicePublicKey: String

    init(licenseKey: String, deviceName: String, proof: DeviceProof) {
        self.licenseKey = licenseKey
        self.deviceName = deviceName
        challengeID = proof.challengeID
        challengeNonce = proof.challengeNonce
        challengeSignature = proof.challengeSignature
        devicePublicKey = proof.devicePublicKey
    }
}

private struct ValidationRequest: Encodable {
    let activationID: String
    let challengeID: String
    let challengeNonce: String
    let challengeSignature: String
    let devicePublicKey: String

    init(activationID: String, proof: DeviceProof) {
        self.activationID = activationID
        challengeID = proof.challengeID
        challengeNonce = proof.challengeNonce
        challengeSignature = proof.challengeSignature
        devicePublicKey = proof.devicePublicKey
    }
}

private struct ChallengeResponse: Decodable {
    let challengeID: String
    let nonce: String
    let message: String
}

private struct ActivationResponse: Decodable {
    let kind: String
    let activationID: String?
    let certificate: String?
    let expiresAt: Date?
}

private struct EmptyResponse: Decodable {}

private struct ServerErrorResponse: Decodable {
    struct Details: Decodable { let message: String }
    let error: Details
}

private let licenseJSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO-8601 date.")
        }
        return date
    }
    return decoder
}()
