import Foundation
import WhisperKit

struct TranscriptionEngine {
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

    func transcribe(audioFileURL: URL) async throws -> String {
        guard FileManager.default.fileExists(atPath: audioFileURL.path) else {
            throw TranscriptionError.audioFileMissing(audioFileURL)
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: audioFileURL.path)
        if (attributes[.size] as? NSNumber)?.int64Value == 0 {
            throw TranscriptionError.audioFileEmpty(audioFileURL)
        }

        let pipeline = try await TranscriptionPipeline.shared.whisperKit()
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
}

private actor TranscriptionPipeline {
    static let shared = TranscriptionPipeline()

    private var cachedWhisperKit: WhisperKit?

    func whisperKit() async throws -> WhisperKit {
        if let cachedWhisperKit {
            return cachedWhisperKit
        }

        let whisperKit = try await WhisperKit()
        cachedWhisperKit = whisperKit
        return whisperKit
    }
}
