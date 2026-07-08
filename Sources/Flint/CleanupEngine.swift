import Foundation

enum CleanupMode: String, CaseIterable {
    case clean
    case verbatim
    case polished
    case prompt
    case message
    case email

    var displayName: String {
        switch self {
        case .verbatim:
            return "Verbatim"
        case .clean:
            return "Clean"
        case .polished:
            return "Polished"
        case .prompt:
            return "Prompt"
        case .message:
            return "Message"
        case .email:
            return "Email"
        }
    }
}

struct CleanupModeSelectionStore {
    let defaults: UserDefaults
    let key: String

    init(defaults: UserDefaults = .standard, key: String = "cleanupMode") {
        self.defaults = defaults
        self.key = key
    }

    func load() -> CleanupMode {
        CleanupMode(rawValue: defaults.string(forKey: key) ?? "") ?? .clean
    }

    func save(_ mode: CleanupMode) {
        defaults.set(mode.rawValue, forKey: key)
    }
}

struct CleanupEngine {
    func clean(_ transcript: String, mode: CleanupMode = .clean) -> String {
        switch mode {
        case .verbatim:
            return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        case .clean:
            return clean(transcript)
        case .polished:
            return polish(transcript)
        case .prompt:
            return makePrompt(transcript)
        case .message:
            return makeMessage(transcript)
        case .email:
            return makeEmail(transcript)
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

    private func polish(_ transcript: String) -> String {
        var text = clean(transcript)
        text = capitalizeStandaloneI(in: text)
        text = normalizeRepeatedTerminalPunctuation(in: text)
        text = normalizeQuestionTerminalPunctuation(in: text)
        return text
    }

    private func makePrompt(_ transcript: String) -> String {
        var text = polish(transcript)
        text = text.replacingOccurrences(
            of: #"(?i)^(?:hey\s+)?(?:chatgpt|claude|cursor|copilot)[,;:]?\s+"#,
            with: "",
            options: .regularExpression
        )
        text = replaceFirstRegex(in: text, pattern: #"(?i)^(?:can|could|would)\s+you\s+please\s+"#, with: "Please ")
        text = replaceFirstRegex(in: text, pattern: #"(?i)^(?:can|could|would)\s+you\s+"#, with: "Please ")
        text = replaceFirstRegex(in: text, pattern: #"(?i)^i\s+need\s+you\s+to\s+"#, with: "Please ")
        text = capitalizeSentenceStarts(in: text)
        text = normalizeInstructionTerminalPunctuation(in: text)
        return text
    }

    private func makeMessage(_ transcript: String) -> String {
        var text = polish(transcript)
        text = text.replacingOccurrences(
            of: #"(?i)^(?:hey|hi|hello)[,;:]\s+"#,
            with: "",
            options: .regularExpression
        )
        text = replaceFirstRegex(in: text, pattern: #"(?i)^could you please\b"#, with: "Could you")
        text = replaceFirstRegex(in: text, pattern: #"(?i)^can you please\b"#, with: "Can you")
        text = replaceFirstRegex(in: text, pattern: #"(?i)^would you please\b"#, with: "Would you")
        text = normalizeQuestionTerminalPunctuation(in: text)
        return text
    }

    private func makeEmail(_ transcript: String) -> String {
        let text = polish(transcript)
        return formatEmailBlockIfUseful(from: text) ?? text
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

    private func capitalizeStandaloneI(in text: String) -> String {
        text.replacingOccurrences(
            of: #"(?i)\bi\b"#,
            with: "I",
            options: .regularExpression
        )
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

    private func normalizeRepeatedTerminalPunctuation(in text: String) -> String {
        text.replacingOccurrences(
            of: #"([.!?]){2,}$"#,
            with: "$1",
            options: .regularExpression
        )
    }

    private func normalizeQuestionTerminalPunctuation(in text: String) -> String {
        guard text.hasSuffix(".") else { return text }
        let questionPattern = #"(?i)^(?:who|what|when|where|why|how|can|could|would|should|will|is|are|do|does|did)\b"#
        guard text.range(of: questionPattern, options: .regularExpression) != nil else {
            return text
        }

        return String(text.dropLast()) + "?"
    }

    private func normalizeInstructionTerminalPunctuation(in text: String) -> String {
        guard text.hasSuffix("?"),
              text.range(of: #"(?i)^please\b"#, options: .regularExpression) != nil else {
            return text
        }

        return String(text.dropLast()) + "."
    }

    private func shouldAddTerminalPunctuation(to text: String) -> Bool {
        guard let last = text.unicodeScalars.last else { return false }
        if CharacterSet.alphanumerics.contains(last) {
            return true
        }
        return false
    }

    private func replaceFirstRegex(in text: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: replacement)
    }

    private func formatEmailBlockIfUseful(from text: String) -> String? {
        let pattern = #"(?i)^(hi|hello|hey|dear)\s+([^,!.?]+)[,!.?]\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        guard let match = regex.firstMatch(in: text, range: fullRange),
              match.numberOfRanges == 4 else {
            return nil
        }

        let greeting = nsText.substring(with: match.range(at: 1))
        let recipient = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
        var body = nsText.substring(with: match.range(at: 3)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !recipient.isEmpty, !body.isEmpty else { return nil }

        var signoff: String?
        let signoffPatterns = [
            (#"(?i)\s+thank you\.?$"#, "Thank you"),
            (#"(?i)\s+thanks\.?$"#, "Thanks")
        ]
        for (pattern, value) in signoffPatterns {
            if body.range(of: pattern, options: .regularExpression) != nil {
                body = body.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
                signoff = value
                break
            }
        }

        body = capitalizeSentenceStarts(in: body.trimmingCharacters(in: .whitespacesAndNewlines))
        if shouldAddTerminalPunctuation(to: body) {
            body += "."
        }

        let salutation = "\(greeting.prefix(1).uppercased())\(greeting.dropFirst().lowercased()) \(recipient),"
        if let signoff {
            return "\(salutation)\n\n\(body)\n\n\(signoff)"
        }
        return "\(salutation)\n\n\(body)"
    }
}
