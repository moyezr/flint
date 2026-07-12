import CryptoKit
import XCTest
@testable import Flint

final class LicenseRuntimeTests: XCTestCase {
    func testCertificateBoundToDeviceAndBundleVerifies() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let deviceKey = Curve25519.Signing.PrivateKey()
        let identity = try LicenseDeviceIdentity(rawRepresentation: deviceKey.rawRepresentation)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let certificate = try makeCertificate(
            signingKey: signingKey,
            deviceIdentity: identity,
            issuedAt: now.addingTimeInterval(-60),
            expiresAt: now.addingTimeInterval(60)
        )

        let verifier = try LicenseCertificateVerifier(
            publicKeyBase64URL: signingKey.publicKey.rawRepresentation.base64URLEncoded(),
            now: { now }
        )

        let payload = try verifier.verify(certificate: certificate, deviceIdentity: identity)

        XCTAssertEqual(payload.activationID, "act_test")
        XCTAssertEqual(payload.appBundleID, FlintLicenseConfiguration.appBundleID)
    }

    func testCertificateCannotBeUsedByAnotherDevice() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let sourceIdentity = try LicenseDeviceIdentity(rawRepresentation: Curve25519.Signing.PrivateKey().rawRepresentation)
        let otherIdentity = try LicenseDeviceIdentity(rawRepresentation: Curve25519.Signing.PrivateKey().rawRepresentation)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let certificate = try makeCertificate(
            signingKey: signingKey,
            deviceIdentity: sourceIdentity,
            issuedAt: now.addingTimeInterval(-60),
            expiresAt: now.addingTimeInterval(60)
        )
        let verifier = try LicenseCertificateVerifier(
            publicKeyBase64URL: signingKey.publicKey.rawRepresentation.base64URLEncoded(),
            now: { now }
        )

        XCTAssertThrowsError(try verifier.verify(certificate: certificate, deviceIdentity: otherIdentity)) { error in
            XCTAssertEqual(error as? LicenseCertificateVerifier.VerificationError, .wrongDevice)
        }
    }

    func testExpiredCertificateIsRejected() throws {
        let signingKey = Curve25519.Signing.PrivateKey()
        let identity = try LicenseDeviceIdentity(rawRepresentation: Curve25519.Signing.PrivateKey().rawRepresentation)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let certificate = try makeCertificate(
            signingKey: signingKey,
            deviceIdentity: identity,
            issuedAt: now.addingTimeInterval(-120),
            expiresAt: now.addingTimeInterval(-60)
        )
        let verifier = try LicenseCertificateVerifier(
            publicKeyBase64URL: signingKey.publicKey.rawRepresentation.base64URLEncoded(),
            now: { now }
        )

        XCTAssertThrowsError(try verifier.verify(certificate: certificate, deviceIdentity: identity)) { error in
            XCTAssertEqual(error as? LicenseCertificateVerifier.VerificationError, .expired)
        }
    }

    private func makeCertificate(
        signingKey: Curve25519.Signing.PrivateKey,
        deviceIdentity: LicenseDeviceIdentity,
        issuedAt: Date,
        expiresAt: Date
    ) throws -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let payload = """
        {"version":1,"licenseID":"lic_test","activationID":"act_test","productID":"flint-macos","appBundleID":"\(FlintLicenseConfiguration.appBundleID)","deviceKeyHash":"\(deviceIdentity.publicKeyHash)","issuedAt":"\(formatter.string(from: issuedAt))","expiresAt":"\(formatter.string(from: expiresAt))"}
        """
        let payloadPart = Data(payload.utf8).base64URLEncoded()
        let signature = try signingKey.signature(for: Data(payloadPart.utf8)).base64URLEncoded()
        return "\(payloadPart).\(signature)"
    }
}

private extension Data {
    func base64URLEncoded() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
