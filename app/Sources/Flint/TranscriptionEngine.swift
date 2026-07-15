import Foundation
import WhisperKit

struct TranscriptionEngine {
    static let noUsableAudioMessage = "No usable audio was captured."
    static let noSpeechDetectedMessage = "No speech detected."
    static let localTranscriptionFailedMessage = "Local transcription failed."

    private let modelManager: ModelManager

    init(modelManager: ModelManager = ModelManager()) {
        self.modelManager = modelManager
    }

    enum TranscriptionError: LocalizedError {
        case audioFileMissing(URL)
        case audioFileEmpty(URL)
        case emptyTranscript

        var errorDescription: String? {
            switch self {
            case .audioFileMissing(let url):
                return "Audio file does not exist: \(url.path)"
            case .audioFileEmpty(let url):
                return "Audio file is empty: \(url.path)"
            case .emptyTranscript:
                return "WhisperKit returned an empty transcript."
            }
        }
    }

    static func userFacingMessage(for error: Error) -> String {
        switch error {
        case TranscriptionError.audioFileMissing, TranscriptionError.audioFileEmpty:
            return noUsableAudioMessage
        case TranscriptionError.emptyTranscript:
            return noSpeechDetectedMessage
        default:
            return localTranscriptionFailedMessage
        }
    }

    func transcribe(audioFileURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw TranscriptionError.audioFileMissing(audioFileURL)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: audioFileURL.path)
        if (attributes[.size] as? NSNumber)?.int64Value == 0 {
            throw TranscriptionError.audioFileEmpty(audioFileURL)
        }

        let descriptor = modelManager.selectedConfigurationDescriptor()
        let pipeline = try await TranscriptionPipeline.shared.whisperKit(for: descriptor)
        let results = try await pipeline.transcribe(audioPath: audioFileURL.path)
        let transcript = results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !transcript.isEmpty else {
            throw TranscriptionError.emptyTranscript
        }

        return transcript
    }

    func prepareSelectedModel() async throws {
        try await prepareModel(for: modelManager.selectedTier())
    }

    func prepareModel(for tier: ModelTier) async throws {
        let descriptor = modelManager.configurationDescriptor(for: tier)
        _ = try await TranscriptionPipeline.shared.whisperKit(for: descriptor)
    }

    static func whisperKitConfigDescriptor(for descriptor: ModelConfigurationDescriptor) -> WhisperKitConfigDescriptor {
        if let modelFolder = descriptor.modelFolder {
            return WhisperKitConfigDescriptor(
                model: nil,
                downloadBase: descriptor.downloadBase,
                modelFolder: modelFolder.path
            )
        }

        return WhisperKitConfigDescriptor(
            model: descriptor.modelName,
            downloadBase: descriptor.downloadBase,
            modelFolder: nil
        )
    }
}

struct WhisperKitConfigDescriptor: Equatable {
    let model: String?
    let downloadBase: URL?
    let modelFolder: String?
}

private actor TranscriptionPipeline {
    static let shared = TranscriptionPipeline()

    private var cachedWhisperKits: [ModelConfigurationDescriptor: WhisperKit] = [:]
    func whisperKit(for descriptor: ModelConfigurationDescriptor) async throws -> WhisperKit {
        if let cachedWhisperKit = cachedWhisperKits[descriptor] {
            return cachedWhisperKit
        }

        let configDescriptor = TranscriptionEngine.whisperKitConfigDescriptor(for: descriptor)
        let config = WhisperKitConfig(
            model: configDescriptor.model,
            downloadBase: configDescriptor.downloadBase,
            modelFolder: configDescriptor.modelFolder
        )
        let whisperKit = try await WhisperKit(config)
        cachedWhisperKits[descriptor] = whisperKit
        return whisperKit
    }
}
