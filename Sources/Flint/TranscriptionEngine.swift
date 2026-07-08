import Foundation

struct TranscriptionEngine {
    func transcribe(audioFileURL: URL) async throws -> String {
        // TODO: Replace this placeholder with an on-device Whisper integration.
        // WhisperKit is likely the cleanest Swift-native first option; whisper.cpp
        // remains a good fallback if packaging, model control, or performance require it.
        let filename = audioFileURL.lastPathComponent
        return "Placeholder local transcript from \(filename)."
    }
}
