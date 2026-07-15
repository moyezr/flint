import Foundation

struct SnapshotVocabularyApplication: Equatable, Sendable {
    let text: String
    let matchedMemoryCounts: [UUID: Int]
    let applicableHeardKeys: Set<String>
}

struct MemorySnapshot: Equatable, Sendable {
    static let empty = MemorySnapshot(memories: [])

    let memories: [LearningMemory]

    private let tokenRoot: VocabularyTrieNode
    private let regexMemories: [CompiledMemory]

    init(memories: [LearningMemory]) {
        let activeMemories = memories
            .filter { memory in
                guard memory.memoryType == .vocabulary, memory.status == .active else { return false }
                return CorrectionMappingPolicy().safety(for: CorrectionProposal(
                    heardForm: memory.heardForm,
                    preferredForm: memory.preferredForm
                )) == .direct
            }
            .sorted(by: Self.applicationOrder)
        self.memories = activeMemories

        let root = VocabularyTrieNode()
        var regexMemories: [CompiledMemory] = []
        for memory in activeMemories {
            if let tokens = Self.simplePhraseTokens(memory.heardForm) {
                root.insert(memory: memory, tokens: tokens)
            } else if let compiled = CompiledMemory(memory: memory) {
                regexMemories.append(compiled)
            }
        }
        tokenRoot = root
        self.regexMemories = regexMemories
    }

    func vocabulary(language: String, applicationBundleID: String?) -> [LearningMemory] {
        let requestedLanguage = Self.requestedLanguage(language)
        var seenKeys: Set<String> = []
        return memories
            .filter {
                Self.isEligible(
                    $0,
                    requestedLanguage: requestedLanguage,
                    applicationBundleID: applicationBundleID
                )
            }
            .sorted {
                Self.precedes(
                    $0,
                    $1,
                    requestedLanguage: requestedLanguage
                )
            }
            .filter { seenKeys.insert($0.heardKey).inserted }
    }

    func applyVocabulary(
        to text: String,
        language: String,
        applicationBundleID: String?
    ) -> SnapshotVocabularyApplication {
        let requestedLanguage = Self.requestedLanguage(language)
        var result = text
        var matchedCounts: [UUID: Int] = [:]

        let tokenMatches = tokenMatches(
            in: result,
            requestedLanguage: requestedLanguage,
            applicationBundleID: applicationBundleID
        )
        if !tokenMatches.isEmpty {
            let mutable = NSMutableString(string: result)
            for match in tokenMatches.reversed() {
                mutable.replaceCharacters(in: match.range, with: match.memory.preferredForm)
                matchedCounts[match.memory.id, default: 0] += 1
            }
            result = mutable as String
        }

        var seenFallbackKeys: Set<String> = []
        let fallbackEntries = regexMemories
            .filter {
                Self.isEligible(
                    $0.memory,
                    requestedLanguage: requestedLanguage,
                    applicationBundleID: applicationBundleID
                )
            }
            .sorted {
                Self.precedes(
                    $0.memory,
                    $1.memory,
                    requestedLanguage: requestedLanguage
                )
            }
            .filter { seenFallbackKeys.insert($0.memory.heardKey).inserted }

        for entry in fallbackEntries {
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            let matches = entry.regularExpression.matches(in: result, range: range)
            guard !matches.isEmpty else { continue }
            let template = NSRegularExpression.escapedTemplate(for: entry.memory.preferredForm)
            result = entry.regularExpression.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: template
            )
            matchedCounts[entry.memory.id, default: 0] += matches.count
        }

        let applicableKeys = Set(memories.lazy.filter {
            Self.isEligible(
                $0,
                requestedLanguage: requestedLanguage,
                applicationBundleID: applicationBundleID
            )
        }.map(\.heardKey))

        return SnapshotVocabularyApplication(
            text: result,
            matchedMemoryCounts: matchedCounts,
            applicableHeardKeys: applicableKeys
        )
    }

    static func == (lhs: MemorySnapshot, rhs: MemorySnapshot) -> Bool {
        lhs.memories == rhs.memories
    }

    private func tokenMatches(
        in text: String,
        requestedLanguage: String,
        applicationBundleID: String?
    ) -> [VocabularyTokenMatch] {
        let tokens = Self.textTokens(text)
        guard !tokens.isEmpty else { return [] }
        let nsText = text as NSString
        var matches: [VocabularyTokenMatch] = []
        var startIndex = 0

        while startIndex < tokens.count {
            var node = tokenRoot
            var tokenIndex = startIndex
            var bestMatch: VocabularyTokenMatch?

            while tokenIndex < tokens.count {
                if tokenIndex > startIndex {
                    let previousRange = tokens[tokenIndex - 1].range
                    let currentRange = tokens[tokenIndex].range
                    let gap = NSRange(
                        location: NSMaxRange(previousRange),
                        length: currentRange.location - NSMaxRange(previousRange)
                    )
                    guard Self.containsOnlyWhitespace(nsText.substring(with: gap)) else { break }
                }

                guard let child = node.children[tokens[tokenIndex].key] else { break }
                node = child
                if let memory = Self.bestEligible(
                    node.endings,
                    requestedLanguage: requestedLanguage,
                    applicationBundleID: applicationBundleID
                ) {
                    bestMatch = VocabularyTokenMatch(
                        memory: memory,
                        range: NSRange(
                            location: tokens[startIndex].range.location,
                            length: NSMaxRange(tokens[tokenIndex].range) - tokens[startIndex].range.location
                        ),
                        finalTokenIndex: tokenIndex
                    )
                }
                tokenIndex += 1
            }

            if let bestMatch {
                matches.append(bestMatch)
                startIndex = bestMatch.finalTokenIndex + 1
            } else {
                startIndex += 1
            }
        }
        return matches
    }

    private static func bestEligible(
        _ memories: [LearningMemory],
        requestedLanguage: String,
        applicationBundleID: String?
    ) -> LearningMemory? {
        memories
            .filter {
                isEligible(
                    $0,
                    requestedLanguage: requestedLanguage,
                    applicationBundleID: applicationBundleID
                )
            }
            .sorted { precedes($0, $1, requestedLanguage: requestedLanguage) }
            .first
    }

    private static func isEligible(
        _ memory: LearningMemory,
        requestedLanguage: String,
        applicationBundleID: String?
    ) -> Bool {
        guard memory.language == "auto" || memory.language == requestedLanguage else { return false }
        switch memory.scopeKind {
        case .global:
            return true
        case .application:
            return !memory.scopeValue.isEmpty && memory.scopeValue == applicationBundleID
        }
    }

    private static func precedes(
        _ lhs: LearningMemory,
        _ rhs: LearningMemory,
        requestedLanguage: String
    ) -> Bool {
        let lhsApp = lhs.scopeKind == .application
        let rhsApp = rhs.scopeKind == .application
        if lhsApp != rhsApp { return lhsApp }

        let lhsExactLanguage = lhs.language == requestedLanguage
        let rhsExactLanguage = rhs.language == requestedLanguage
        if lhsExactLanguage != rhsExactLanguage { return lhsExactLanguage }

        if lhs.heardKey.count != rhs.heardKey.count {
            return lhs.heardKey.count > rhs.heardKey.count
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func applicationOrder(_ lhs: LearningMemory, _ rhs: LearningMemory) -> Bool {
        if lhs.scopeKind != rhs.scopeKind { return lhs.scopeKind == .application }
        if lhs.heardKey.count != rhs.heardKey.count {
            return lhs.heardKey.count > rhs.heardKey.count
        }
        return lhs.updatedAt > rhs.updatedAt
    }

    private static func requestedLanguage(_ language: String) -> String {
        let trimmed = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "auto" : trimmed
    }

    private static func simplePhraseTokens(_ phrase: String) -> [String]? {
        let words = phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \Character.isWhitespace)
            .map(String.init)
        guard !words.isEmpty,
              words.allSatisfy({ word in
                  !word.isEmpty && word.unicodeScalars.allSatisfy(CharacterSet.alphanumerics.contains)
              }) else { return nil }
        return words.map(VocabularyNormalizer.key)
    }

    private static func textTokens(_ text: String) -> [VocabularyTextToken] {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return WordExpression.shared.matches(in: text, range: range).compactMap { match in
            guard let tokenRange = Range(match.range, in: text) else { return nil }
            return VocabularyTextToken(
                key: VocabularyNormalizer.key(for: String(text[tokenRange])),
                range: match.range
            )
        }
    }

    private static func containsOnlyWhitespace(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy(CharacterSet.whitespacesAndNewlines.contains)
    }
}

private final class VocabularyTrieNode: @unchecked Sendable {
    var children: [String: VocabularyTrieNode] = [:]
    var endings: [LearningMemory] = []

    func insert(memory: LearningMemory, tokens: [String]) {
        var node = self
        for token in tokens {
            if let child = node.children[token] {
                node = child
            } else {
                let child = VocabularyTrieNode()
                node.children[token] = child
                node = child
            }
        }
        node.endings.append(memory)
    }
}

private struct VocabularyTextToken {
    let key: String
    let range: NSRange
}

private struct VocabularyTokenMatch {
    let memory: LearningMemory
    let range: NSRange
    let finalTokenIndex: Int
}

private enum WordExpression {
    static let shared = try! NSRegularExpression(pattern: #"[\p{L}\p{N}]+"#)
}

private struct CompiledMemory: @unchecked Sendable {
    let memory: LearningMemory
    let regularExpression: NSRegularExpression

    init?(memory: LearningMemory) {
        let words = memory.heardForm
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \Character.isWhitespace)
        guard !words.isEmpty, !memory.preferredForm.isEmpty else { return nil }

        let phrasePattern = words
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: #"\s+"#)
        let pattern = #"(?<![[:alnum:]])"# + phrasePattern + #"(?![[:alnum:]])"#
        guard let regularExpression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return nil }

        self.memory = memory
        self.regularExpression = regularExpression
    }
}
