import Foundation

struct UpdateConfiguration: Equatable {
    let bundleIdentifier: String
    let currentVersion: String
    let currentBuild: String
    let manifestURL: URL
}

enum UpdateReadiness: Equatable {
    case ready(UpdateConfiguration)
    case notConfigured(prerequisites: [String])
}

struct UpdateRelease: Equatable, Decodable {
    let version: String
    let build: String?
    let downloadURL: URL
    let publishedAt: String?
    let minimumSystemVersion: String?
    let sha256: String?
    let notes: [String]

    private enum CodingKeys: String, CodingKey {
        case version
        case build
        case downloadURL
        case publishedAt
        case minimumSystemVersion
        case sha256
        case notes
    }

    init(
        version: String,
        build: String? = nil,
        downloadURL: URL,
        publishedAt: String? = nil,
        minimumSystemVersion: String? = nil,
        sha256: String? = nil,
        notes: [String] = []
    ) {
        self.version = version
        self.build = build
        self.downloadURL = downloadURL
        self.publishedAt = publishedAt
        self.minimumSystemVersion = minimumSystemVersion
        self.sha256 = sha256
        self.notes = notes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        build = try container.decodeIfPresent(String.self, forKey: .build)
        downloadURL = try container.decode(URL.self, forKey: .downloadURL)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
        minimumSystemVersion = try container.decodeIfPresent(String.self, forKey: .minimumSystemVersion)
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)
        notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []
    }
}

enum UpdateCheckResult: Equatable {
    case upToDate
    case updateAvailable(UpdateRelease)
}

enum UpdateCheckError: LocalizedError, Equatable {
    case notConfigured([String])
    case invalidResponse
    case invalidManifest

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Update checking is unavailable in this build."
        case .invalidResponse:
            return "Flint could not reach the update service."
        case .invalidManifest:
            return "The update service returned an invalid release."
        }
    }
}

struct UpdateManager {
    typealias DataLoader = (URLRequest) async throws -> (Data, URLResponse)

    private let metadata: [String: Any]
    private let bundleURL: URL
    private let dataLoader: DataLoader

    init(
        metadata: [String: Any] = Bundle.main.infoDictionary ?? [:],
        bundleURL: URL = Bundle.main.bundleURL,
        dataLoader: @escaping DataLoader = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.metadata = metadata
        self.bundleURL = bundleURL
        self.dataLoader = dataLoader
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

        let currentBuild = nonEmptyString(forKey: "CFBundleVersion")
        if currentBuild == nil {
            missing.append("CFBundleVersion")
        }

        let currentVersion = nonEmptyString(forKey: "CFBundleShortVersionString")
        if currentVersion == nil {
            missing.append("CFBundleShortVersionString")
        }

        let manifestURL = validHTTPSURL(forKey: "FlintUpdateManifestURL")
        if manifestURL == nil {
            missing.append("HTTPS FlintUpdateManifestURL")
        }

        guard missing.isEmpty,
              let bundleIdentifier,
              let currentBuild,
              let currentVersion,
              let manifestURL else {
            return .notConfigured(prerequisites: missing)
        }

        return .ready(UpdateConfiguration(
            bundleIdentifier: bundleIdentifier,
            currentVersion: currentVersion,
            currentBuild: currentBuild,
            manifestURL: manifestURL
        ))
    }

    func checkForUpdates() async throws -> UpdateCheckResult {
        guard case .ready(let configuration) = readiness() else {
            if case .notConfigured(let prerequisites) = readiness() {
                throw UpdateCheckError.notConfigured(prerequisites)
            }
            throw UpdateCheckError.notConfigured([])
        }

        var request = URLRequest(
            url: configuration.manifestURL,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 8
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await dataLoader(request)
        guard let response = response as? HTTPURLResponse,
              response.statusCode == 200 else {
            throw UpdateCheckError.invalidResponse
        }

        let release: UpdateRelease
        do {
            release = try JSONDecoder().decode(UpdateRelease.self, from: data)
        } catch {
            throw UpdateCheckError.invalidManifest
        }

        guard release.downloadURL.scheme?.lowercased() == "https",
              release.downloadURL.host?.isEmpty == false,
              VersionNumber(release.version) != nil else {
            throw UpdateCheckError.invalidManifest
        }

        return isNewer(release, than: configuration) ? .updateAvailable(release) : .upToDate
    }

    private func isNewer(_ release: UpdateRelease, than configuration: UpdateConfiguration) -> Bool {
        guard let availableVersion = VersionNumber(release.version),
              let currentVersion = VersionNumber(configuration.currentVersion) else {
            return false
        }

        if availableVersion != currentVersion {
            return availableVersion > currentVersion
        }

        guard let availableBuild = release.build else {
            return false
        }
        return compareBuild(availableBuild, configuration.currentBuild) == .orderedDescending
    }

    private func compareBuild(_ lhs: String, _ rhs: String) -> ComparisonResult {
        if let lhsNumber = Int(lhs), let rhsNumber = Int(rhs) {
            if lhsNumber == rhsNumber { return .orderedSame }
            return lhsNumber > rhsNumber ? .orderedDescending : .orderedAscending
        }
        return lhs.compare(rhs, options: [.numeric, .caseInsensitive])
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
}

struct UpdateCheckPolicy {
    let interval: TimeInterval

    init(interval: TimeInterval = 24 * 60 * 60) {
        self.interval = interval
    }

    func shouldCheck(lastSuccessfulCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastSuccessfulCheck else { return true }
        return now.timeIntervalSince(lastSuccessfulCheck) >= interval
    }
}

struct UpdateCheckStore {
    private enum Key {
        static let lastSuccessfulCheck = "updateLastSuccessfulCheck"
        static let lastNotifiedVersion = "updateLastNotifiedVersion"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var lastSuccessfulCheck: Date? {
        defaults.object(forKey: Key.lastSuccessfulCheck) as? Date
    }

    var lastNotifiedVersion: String? {
        defaults.string(forKey: Key.lastNotifiedVersion)
    }

    func markSuccessfulCheck(at date: Date = Date()) {
        defaults.set(date, forKey: Key.lastSuccessfulCheck)
    }

    func markNotified(version: String) {
        defaults.set(version, forKey: Key.lastNotifiedVersion)
    }
}

private struct VersionNumber: Comparable {
    private enum Identifier: Equatable {
        case number(Int)
        case text(String)
    }

    private let core: [Int]
    private let prerelease: [Identifier]

    init?(_ rawValue: String) {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let version = trimmed.hasPrefix("v") ? String(trimmed.dropFirst()) : trimmed
        let withoutBuildMetadata = version.split(separator: "+", maxSplits: 1).first.map(String.init) ?? version
        let pieces = withoutBuildMetadata.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let corePieces = pieces[0].split(separator: ".", omittingEmptySubsequences: false)
        guard !corePieces.isEmpty,
              corePieces.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }

        core = corePieces.map { Int($0)! }
        if pieces.count == 2 {
            let identifiers = pieces[1].split(separator: ".", omittingEmptySubsequences: false)
            guard !identifiers.isEmpty, identifiers.allSatisfy({ !$0.isEmpty }) else { return nil }
            prerelease = identifiers.map { identifier in
                if identifier.allSatisfy(\.isNumber), let number = Int(identifier) {
                    return .number(number)
                }
                return .text(identifier.lowercased())
            }
        } else {
            prerelease = []
        }
    }

    static func < (lhs: VersionNumber, rhs: VersionNumber) -> Bool {
        let coreCount = max(lhs.core.count, rhs.core.count)
        for index in 0..<coreCount {
            let left = index < lhs.core.count ? lhs.core[index] : 0
            let right = index < rhs.core.count ? rhs.core[index] : 0
            if left != right { return left < right }
        }

        if lhs.prerelease.isEmpty != rhs.prerelease.isEmpty {
            return !lhs.prerelease.isEmpty
        }

        for index in 0..<min(lhs.prerelease.count, rhs.prerelease.count) {
            let left = lhs.prerelease[index]
            let right = rhs.prerelease[index]
            if left == right { continue }
            switch (left, right) {
            case (.number(let leftNumber), .number(let rightNumber)):
                return leftNumber < rightNumber
            case (.number, .text):
                return true
            case (.text, .number):
                return false
            case (.text(let leftText), .text(let rightText)):
                return leftText < rightText
            }
        }

        return lhs.prerelease.count < rhs.prerelease.count
    }
}
