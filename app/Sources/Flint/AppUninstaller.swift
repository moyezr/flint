import AppKit
import Foundation

struct AppUninstaller {
    enum AppUninstallerError: LocalizedError, Equatable {
        case installedAppRequired
        case unexpectedBundleIdentifier(String?)
        case applicationNotFound(URL)
        case applicationIsOnReadOnlyVolume(URL)
        case applicationWasNotMovedToTrash(URL)

        var errorDescription: String? {
            switch self {
            case .installedAppRequired:
                return "Uninstall is available only from the packaged Flint.app. Local data was not deleted."
            case let .unexpectedBundleIdentifier(identifier):
                let displayIdentifier = identifier ?? "none"
                return "Refusing to remove an application with bundle identifier \(displayIdentifier). Local data was not deleted."
            case let .applicationNotFound(url):
                return "Flint.app was not found at \(url.path). Local data was not deleted."
            case let .applicationIsOnReadOnlyVolume(url):
                return "Flint.app at \(url.path) is on a read-only volume. Open the copy installed in Applications before uninstalling. Local data was not deleted."
            case let .applicationWasNotMovedToTrash(url):
                return "Finder did not move Flint.app at \(url.path) to Trash."
            }
        }
    }

    typealias Recycler = ([URL]) async throws -> [URL: URL]

    static let expectedBundleIdentifier = "com.moyezrabbani.Flint"

    private let applicationURLProvider: () -> URL
    private let bundleIdentifierProvider: () -> String?
    private let fileExists: (String) -> Bool
    private let isVolumeReadOnly: (URL) throws -> Bool
    private let recycler: Recycler

    init(
        applicationURLProvider: @escaping () -> URL,
        bundleIdentifierProvider: @escaping () -> String?,
        fileExists: @escaping (String) -> Bool = FileManager.default.fileExists(atPath:),
        isVolumeReadOnly: @escaping (URL) throws -> Bool = {
            try $0.resourceValues(forKeys: [.volumeIsReadOnlyKey]).volumeIsReadOnly ?? false
        },
        recycler: @escaping Recycler
    ) {
        self.applicationURLProvider = applicationURLProvider
        self.bundleIdentifierProvider = bundleIdentifierProvider
        self.fileExists = fileExists
        self.isVolumeReadOnly = isVolumeReadOnly
        self.recycler = recycler
    }

    func validatedApplicationURL() throws -> URL {
        let applicationURL = applicationURLProvider().standardizedFileURL
        guard applicationURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame else {
            throw AppUninstallerError.installedAppRequired
        }
        let bundleIdentifier = bundleIdentifierProvider()
        guard bundleIdentifier == Self.expectedBundleIdentifier else {
            throw AppUninstallerError.unexpectedBundleIdentifier(bundleIdentifier)
        }
        guard fileExists(applicationURL.path) else {
            throw AppUninstallerError.applicationNotFound(applicationURL)
        }
        guard try !isVolumeReadOnly(applicationURL) else {
            throw AppUninstallerError.applicationIsOnReadOnlyVolume(applicationURL)
        }
        return applicationURL
    }

    func moveApplicationToTrash(_ applicationURL: URL) async throws {
        let validatedURL = try validatedApplicationURL()
        guard validatedURL == applicationURL.standardizedFileURL else {
            throw AppUninstallerError.applicationNotFound(applicationURL)
        }

        let movedURLs = try await recycler([validatedURL])
        let didMoveApplication = movedURLs.keys.contains { sourceURL in
            sourceURL.standardizedFileURL == validatedURL
        }
        guard didMoveApplication else {
            throw AppUninstallerError.applicationWasNotMovedToTrash(validatedURL)
        }
    }

    static let live = AppUninstaller(
        applicationURLProvider: { Bundle.main.bundleURL },
        bundleIdentifierProvider: { Bundle.main.bundleIdentifier },
        recycler: { urls in
            try await NSWorkspace.shared.recycle(urls)
        }
    )
}
