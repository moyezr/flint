import Foundation

enum CleanupMode: String, CaseIterable {
    case clean
    case verbatim

    var displayName: String {
        switch self {
        case .clean:
            return "Clean"
        case .verbatim:
            return "Verbatim"
        }
    }
}

struct CleanupEngine {
    func clean(_ transcript: String, mode: CleanupMode = .clean) -> String {
        switch mode {
        case .verbatim:
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        case .clean:
            return clean(transcript)
        }
    }

    private func clean(_ transcript: String) -> String {
        var text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }

        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = removeFillers(from: text)
        text = text.replacingOccurrences(of: #"\s+([,.;:!?])"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = capitalizeSentenceStarts(in: text)

        if shouldAddTerminalPunctuation(to: text) {
            text += "."
        }

        return text
    }

    private func removeFillers(from text: String) -> String {
        var result = text

        let fillerWords = #"um+|uh+|erm|er|ah"#
        result = result.replacingOccurrences(
            of: #"(?i)^(?:"# + fillerWords + #")[,;:]?\s+"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)^(?:you know|like)[,;:]\s+"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)\s*[,;:]\s*(?:(?:"# + fillerWords + #")|you know|like)\s*[,;:]\s*"#,
            with: " ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)\b(?:"# + fillerWords + #")\b[,;:]?\s*"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)\s+[,;:]?\s*(?:"# + fillerWords + #")$"#,
            with: "",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"(?i)\s*[,;:]\s*you know$"#,
            with: "",
            options: .regularExpression
        )

        return result
    }

    private func capitalizeSentenceStarts(in text: String) -> String {
        let pattern = #"(^|[.!?]\s+)([a-z][A-Za-z']*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return text
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).reversed()
        let result = NSMutableString(string: text)

        for match in matches {
            let wordRange = match.range(at: 2)
            let word = nsText.substring(with: wordRange)
            guard word == word.lowercased() else { continue }

            let capitalized = word.prefix(1).uppercased() + word.dropFirst()
            result.replaceCharacters(in: wordRange, with: capitalized)
        }

        return result as String
    }

    private func shouldAddTerminalPunctuation(to text: String) -> Bool {
        guard let last = text.unicodeScalars.last else { return false }
        if CharacterSet.alphanumerics.contains(last) {
            return true
        }
        return false
    }
}
