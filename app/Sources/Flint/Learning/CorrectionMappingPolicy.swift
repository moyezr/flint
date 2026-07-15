import Foundation

enum CorrectionMappingSafety: Equatable, Sendable {
    case direct
    case contextRequired
}

struct CorrectionMappingPolicy: Sendable {
    func safety(for proposal: CorrectionProposal) -> CorrectionMappingSafety {
        let heardTokens = tokens(in: proposal.heardForm)
        let preferredTokens = tokens(in: proposal.preferredForm)

        if isSingleWordHomophoneAmbiguity(heardTokens: heardTokens, preferredTokens: preferredTokens) {
            return .contextRequired
        }

        let preferredUsesEntityStyling = proposal.preferredForm.unicodeScalars.contains { scalar in
            CharacterSet(charactersIn: ".+#/@").contains(scalar)
        }
        if preferredUsesEntityStyling,
           !heardTokens.isEmpty,
           heardTokens.count <= 4,
           heardTokens.allSatisfy(Self.commonNaturalLanguageWords.contains) {
            return .contextRequired
        }

        return .direct
    }

    private func tokens(in phrase: String) -> [String] {
        phrase
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func isSingleWordHomophoneAmbiguity(
        heardTokens: [String],
        preferredTokens: [String]
    ) -> Bool {
        guard heardTokens.count == 1, preferredTokens.count == 1 else { return false }
        return Self.homophoneGroups.contains { group in
            group.contains(heardTokens[0]) && group.contains(preferredTokens[0])
        }
    }

    private static let homophoneGroups: [Set<String>] = [
        ["to", "too", "two"],
        ["there", "their", "theyre"],
        ["your", "youre"],
        ["right", "write", "rite"],
        ["hear", "here"],
        ["no", "know"],
        ["new", "knew"],
        ["weather", "whether"],
        ["which", "witch"],
        ["than", "then"]
    ]

    private static let commonNaturalLanguageWords: Set<String> = [
        "a", "about", "after", "again", "all", "also", "an", "and", "any", "are", "around", "as", "at",
        "back", "be", "because", "been", "before", "being", "between", "both", "but", "by",
        "can", "come", "could", "day", "did", "do", "does", "doing", "down", "during",
        "each", "end", "even", "every", "few", "first", "for", "from", "get", "give", "go", "going", "good",
        "had", "has", "have", "he", "her", "here", "him", "his", "how", "i", "if", "in", "into", "is", "it", "its",
        "just", "know", "last", "later", "like", "long", "look", "make", "many", "may", "me", "more", "most", "much", "my",
        "new", "next", "no", "not", "now", "of", "off", "on", "one", "only", "or", "other", "our", "out", "over",
        "people", "right", "same", "say", "see", "she", "should", "so", "some", "still", "take", "than", "that", "the", "their",
        "them", "then", "there", "these", "they", "thing", "think", "this", "those", "through", "time", "to", "too", "two",
        "under", "up", "us", "use", "very", "want", "was", "way", "we", "well", "were", "what", "when", "where", "which", "while",
        "who", "why", "will", "with", "work", "would", "year", "you", "your"
    ]
}
