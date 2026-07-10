import Foundation
import WhisperKit

enum ModelTier: String, CaseIterable, Equatable {
    case fast
    case balanced
    case accurate

    var displayName: String {
        switch self {
        case .fast:
            return "Fast"
        case .balanced:
            return "Balanced"
        case .accurate:
            return "Accurate"
        }
    }

    var modelName: String {
        switch self {
        case .fast:
            return "tiny"
        case .balanced:
            return "base"
        case .accurate:
            return "large-v3-v20240930_626MB"
        }
    }

    var sizeLabel: String {
        switch self {
        case .fast:
            return "Small"
        case .balanced:
            return "Medium"
        case .accurate:
            return "~626 MB"
        }
    }

    var hardwareLabel: String {
        switch self {
        case .fast:
            return "Recommended for older Macs"
        case .balanced:
            return "Recommended for most Macs"
        case .accurate:
            return "Recommended for Apple Silicon"
        }
    }
}

struct ModelMetadata: Equatable {
    let tier: ModelTier
    let displayName: String
    let modelName: String
    let sizeLabel: String
    let hardwareLabel: String
    let isInstalled: Bool
    let installedFolder: URL?
}

struct ModelConfigurationDescriptor: Equatable, Hashable {
    let tier: ModelTier
    let modelName: String
    let downloadBase: URL
    let modelFolder: URL?
}

struct ModelManager {
    typealias Downloader = (String, URL?, ProgressCallback?) async throws -> URL

    enum ModelManagerError: LocalizedError, Equatable {
        case savedPathOutsideCacheRoot(URL)

        var errorDescription: String? {
            switch self {
            case .savedPathOutsideCacheRoot(let url):
                return "Refusing to delete model path outside Flint's model cache: \(url.path)"
            }
        }
    }

    private let defaults: UserDefaults
    private let selectedTierKey: String
    private let installedFolderKeyPrefix: String
    let modelCacheRoot: URL
    private let fileManager: FileManager
    private let downloader: Downloader

    init(
        defaults: UserDefaults = .standard,
        selectedTierKey: String = "selectedModelTier",
        installedFolderKeyPrefix: String = "installedModelFolder",
        modelCacheRoot: URL = ModelManager.defaultModelCacheRoot(),
        fileManager: FileManager = .default,
        downloader: @escaping Downloader = ModelManager.productionDownloader
    ) {
        self.defaults = defaults
        self.selectedTierKey = selectedTierKey
        self.installedFolderKeyPrefix = installedFolderKeyPrefix
        self.modelCacheRoot = modelCacheRoot
        self.fileManager = fileManager
        self.downloader = downloader
    }

    static func defaultModelCacheRoot() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return applicationSupport
            .appendingPathComponent("Flint", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    static func productionDownloader(
        variant: String,
        downloadBase: URL?,
        progressCallback: ProgressCallback?
    ) async throws -> URL {
        try await WhisperKit.download(
            variant: variant,
            downloadBase: downloadBase,
            progressCallback: progressCallback
        )
    }

    func selectedTier() -> ModelTier {
        ModelTier(rawValue: defaults.string(forKey: selectedTierKey) ?? "") ?? .balanced
    }

    func saveSelectedTier(_ tier: ModelTier) {
        defaults.set(tier.rawValue, forKey: selectedTierKey)
    }

    func metadata() -> [ModelMetadata] {
        ModelTier.allCases.map(metadata(for:))
    }

    func metadata(for tier: ModelTier) -> ModelMetadata {
        let installedFolder = existingSavedFolder(for: tier)
        return ModelMetadata(
            tier: tier,
            displayName: tier.displayName,
            modelName: tier.modelName,
            sizeLabel: tier.sizeLabel,
            hardwareLabel: tier.hardwareLabel,
            isInstalled: installedFolder != nil,
            installedFolder: installedFolder
        )
    }

    func selectedConfigurationDescriptor() -> ModelConfigurationDescriptor {
        configurationDescriptor(for: selectedTier())
    }

    func configurationDescriptor(for tier: ModelTier) -> ModelConfigurationDescriptor {
        ModelConfigurationDescriptor(
            tier: tier,
            modelName: tier.modelName,
            downloadBase: modelCacheRoot,
            modelFolder: existingSavedFolder(for: tier)
        )
    }

    @discardableResult
    func downloadSelectedModel(progressCallback: ProgressCallback? = nil) async throws -> ModelMetadata {
        try await downloadModel(for: selectedTier(), progressCallback: progressCallback)
    }

    @discardableResult
    func downloadModel(for tier: ModelTier, progressCallback: ProgressCallback? = nil) async throws -> ModelMetadata {
        if existingSavedFolder(for: tier) != nil {
            return metadata(for: tier)
        }

        try fileManager.createDirectory(at: modelCacheRoot, withIntermediateDirectories: true)
        let folder = try await downloader(tier.modelName, modelCacheRoot, progressCallback)
        saveInstalledFolder(folder, for: tier)
        return metadata(for: tier)
    }

    func deleteSelectedModel() throws {
        try deleteModel(for: selectedTier())
    }

    func deleteModel(for tier: ModelTier) throws {
        guard let savedFolder = savedFolder(for: tier) else {
            return
        }

        guard isInsideModelCacheRoot(savedFolder) else {
            throw ModelManagerError.savedPathOutsideCacheRoot(savedFolder)
        }

        if fileManager.fileExists(atPath: savedFolder.path) {
            try fileManager.removeItem(at: savedFolder)
        }
        defaults.removeObject(forKey: installedFolderKey(for: tier))
    }

    func deleteAllCachedModelsAndReferences() throws {
        for tier in ModelTier.allCases {
            guard let savedFolder = savedFolder(for: tier) else {
                continue
            }
            guard isInsideModelCacheRoot(savedFolder) else {
                throw ModelManagerError.savedPathOutsideCacheRoot(savedFolder)
            }
        }

        if fileManager.fileExists(atPath: modelCacheRoot.path) {
            let cachedItems = try fileManager.contentsOfDirectory(
                at: modelCacheRoot,
                includingPropertiesForKeys: nil
            )
            for item in cachedItems {
                try fileManager.removeItem(at: item)
            }
        }

        for tier in ModelTier.allCases {
            defaults.removeObject(forKey: installedFolderKey(for: tier))
        }
    }

    private func existingSavedFolder(for tier: ModelTier) -> URL? {
        guard let folder = savedFolder(for: tier),
              fileManager.fileExists(atPath: folder.path) else {
            return nil
        }
        return folder
    }

    private func savedFolder(for tier: ModelTier) -> URL? {
        guard let path = defaults.string(forKey: installedFolderKey(for: tier)), !path.isEmpty else {
            return nil
        }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func saveInstalledFolder(_ folder: URL, for tier: ModelTier) {
        defaults.set(folder.path, forKey: installedFolderKey(for: tier))
    }

    private func installedFolderKey(for tier: ModelTier) -> String {
        "\(installedFolderKeyPrefix).\(tier.rawValue)"
    }

    private func isInsideModelCacheRoot(_ url: URL) -> Bool {
        let rootPath = modelCacheRoot.standardizedFileURL.path
        let candidatePath = url.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}
