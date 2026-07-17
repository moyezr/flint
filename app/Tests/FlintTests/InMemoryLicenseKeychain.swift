import Foundation
import Security
@testable import Flint

final class TestLicenseKeychainStore {
    private(set) var data: Data?

    lazy var client = LicenseKeychainClient(
        copyMatching: { [weak self] _, result in
            guard let data = self?.data else { return errSecItemNotFound }
            result?.pointee = data as CFData
            return errSecSuccess
        },
        update: { [weak self] _, attributes in
            guard self?.data != nil else { return errSecItemNotFound }
            guard let data = (attributes as NSDictionary)[kSecValueData as String] as? Data else {
                return errSecParam
            }
            self?.data = data
            return errSecSuccess
        },
        add: { [weak self] query, _ in
            guard self?.data == nil else { return errSecDuplicateItem }
            guard let data = (query as NSDictionary)[kSecValueData as String] as? Data else {
                return errSecParam
            }
            self?.data = data
            return errSecSuccess
        },
        delete: { [weak self] _ in
            guard self?.data != nil else { return errSecItemNotFound }
            self?.data = nil
            return errSecSuccess
        }
    )

    func replaceData(_ data: Data?) {
        self.data = data
    }
}
