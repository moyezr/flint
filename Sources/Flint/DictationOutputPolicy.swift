import Foundation

enum DictationOutputPolicy {
    static let emptyOutputMessage = TranscriptionEngine.noSpeechDetectedMessage

    static func usableOutput(from text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.isEmpty ? nil : trimmedText
    }
}
