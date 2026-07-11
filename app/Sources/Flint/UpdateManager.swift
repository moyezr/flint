import Foundation

struct UpdateConfiguration: Equatable {
    let bundleIdentifier: String
    let bundleVersion: String
    let shortVersion: String
    let feedURL: URL
}

enum UpdateReadiness: Equatable {
    case ready(UpdateConfiguration)
    case notConfigured(prerequisites: [String])
}

struct UpdateManager {
    private let metadata: [String: Any]
    private let bundleURL: URL

    init(
        metadata: [String: Any] = Bundle.main.infoDictionary ?? [:],
        bundleURL: URL = Bundle.main.bundleURL
    ) {
        self.metadata = metadata
        self.bundleURL = bundleURL
    }

    func readiness() -> UpdateReadiness {
        var missing: [String] = []

        if bundleURL.pathExtension.lowercased() != "app" {
            missing.append("Application bundle packaging (.app)")
        }

        let bundleIdentifier = nonEmptyString(forKey: "CFBundleIdentifier")
        if bundleIdentifier == nil {
            missing.append("CFBundleIdentifier")
        }

        let bundleVersion = nonEmptyString(forKey: "CFBundleVersion")
        if bundleVersion == nil {
            missing.append("CFBundleVersion")
        }

        let shortVersion = nonEmptyString(forKey: "CFBundleShortVersionString")
        if shortVersion == nil {
            missing.append("CFBundleShortVersionString")
        }

        let feedURL = validHTTPSURL(forKey: "SUFeedURL")
        if feedURL == nil {
            missing.append("HTTPS SUFeedURL")
        }

        if validEdDSAPublicKey(forKey: "SUPublicEDKey") == nil {
            missing.append("SUPublicEDKey")
        }

        guard missing.isEmpty,
              let bundleIdentifier,
              let bundleVersion,
              let shortVersion,
              let feedURL else {
            return .notConfigured(prerequisites: missing)
        }

        return .ready(UpdateConfiguration(
            bundleIdentifier: bundleIdentifier,
            bundleVersion: bundleVersion,
            shortVersion: shortVersion,
            feedURL: feedURL
        ))
    }

    private func nonEmptyString(forKey key: String) -> String? {
        guard let value = metadata[key] as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func validHTTPSURL(forKey key: String) -> URL? {
        guard let rawURL = nonEmptyString(forKey: key),
              let components = URLComponents(string: rawURL),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              let url = components.url else {
            return nil
        }
        return url
    }

    private func validEdDSAPublicKey(forKey key: String) -> Data? {
        guard let rawKey = nonEmptyString(forKey: key),
              let key = Data(base64Encoded: rawKey),
              key.count == 32 else {
            return nil
        }
        return key
    }
}
