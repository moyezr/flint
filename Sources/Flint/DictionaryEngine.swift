import Foundation

struct DictionaryReplacement: Codable, Equatable, Identifiable {
    let id: UUID
    var heardPhrase: String
    var preferredReplacement: String
    var category: String
    var usageCount: Int
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        heardPhrase: String,
        preferredReplacement: String,
        category: String = "custom",
        usageCount: Int = 0,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.heardPhrase = heardPhrase
        self.preferredReplacement = preferredReplacement
        self.category = category
        self.usageCount = usageCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct DictionaryEngine {
    private let userDefaults: UserDefaults
    private let customReplacementsKey = "dictionary.customReplacements"

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    var defaultReplacements: [DictionaryReplacement] {
        [
            defaultReplacement(id: "00000000-0000-0000-0000-000000000001", heardPhrase: "api", preferredReplacement: "API"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000002", heardPhrase: "a p i", preferredReplacement: "API"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000003", heardPhrase: "json", preferredReplacement: "JSON"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000004", heardPhrase: "j son", preferredReplacement: "JSON"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000005", heardPhrase: "post gress", preferredReplacement: "Postgres"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000006", heardPhrase: "postgres", preferredReplacement: "Postgres"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000007", heardPhrase: "docker", preferredReplacement: "Docker"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000008", heardPhrase: "kubernetes", preferredReplacement: "Kubernetes"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000009", heardPhrase: "type script", preferredReplacement: "TypeScript"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000010", heardPhrase: "typescript", preferredReplacement: "TypeScript"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000011", heardPhrase: "next js", preferredReplacement: "Next.js"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000012", heardPhrase: "next dot js", preferredReplacement: "Next.js"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000013", heardPhrase: "github", preferredReplacement: "GitHub"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000014", heardPhrase: "git hub", preferredReplacement: "GitHub"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000015", heardPhrase: "javascript", preferredReplacement: "JavaScript"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000016", heardPhrase: "java script", preferredReplacement: "JavaScript"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000017", heardPhrase: "swift ui", preferredReplacement: "SwiftUI"),
            defaultReplacement(id: "00000000-0000-0000-0000-000000000018", heardPhrase: "sqlite", preferredReplacement: "SQLite")
        ]
    }

    func listReplacements() -> [DictionaryReplacement] {
        sortedForApplication(listCustomReplacements() + defaultReplacements)
    }

    func listCustomReplacements() -> [DictionaryReplacement] {
        guard let data = userDefaults.data(forKey: customReplacementsKey),
              let replacements = try? JSONDecoder().decode([DictionaryReplacement].self, from: data)
        else {
            return []
        }
        return replacements
    }

    @discardableResult
    func addReplacement(
        heardPhrase: String,
        preferredReplacement: String,
        category: String = "custom"
    ) -> DictionaryReplacement {
        let replacement = DictionaryReplacement(
            heardPhrase: heardPhrase.trimmingCharacters(in: .whitespacesAndNewlines),
            preferredReplacement: preferredReplacement.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        var replacements = listCustomReplacements()
        replacements.append(replacement)
        saveCustomReplacements(replacements)
        return replacement
    }

    func removeReplacement(id: UUID) {
        let replacements = listCustomReplacements().filter { $0.id != id }
        saveCustomReplacements(replacements)
    }

    func incrementUsageCount(for id: UUID, by amount: Int = 1) {
        guard amount > 0 else { return }

        var replacements = listCustomReplacements()
        guard let index = replacements.firstIndex(where: { $0.id == id }) else { return }

        replacements[index].usageCount += amount
        replacements[index].updatedAt = Date()
        saveCustomReplacements(replacements)
    }

    func apply(to transcript: String) -> String {
        var result = transcript

        for replacement in listReplacements() {
            let updatedText = apply(replacement, to: result)
            result = updatedText.text

            if updatedText.replacementCount > 0, replacement.category != "default" {
                incrementUsageCount(for: replacement.id, by: updatedText.replacementCount)
            }
        }

        return result
    }

    private func apply(_ replacement: DictionaryReplacement, to text: String) -> (text: String, replacementCount: Int) {
        guard let regex = regex(for: replacement) else {
            return (text, 0)
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, range: range)
        guard !matches.isEmpty else {
            return (text, 0)
        }

        let template = NSRegularExpression.escapedTemplate(for: replacement.preferredReplacement)
        let updatedText = regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
        return (updatedText, matches.count)
    }

    private func regex(for replacement: DictionaryReplacement) -> NSRegularExpression? {
        let words = replacement.heardPhrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace })

        guard !words.isEmpty, !replacement.preferredReplacement.isEmpty else {
            return nil
        }

        let phrasePattern = words
            .map { NSRegularExpression.escapedPattern(for: String($0)) }
            .joined(separator: #"\s+"#)
        let pattern = #"(?<![[:alnum:]])"# + phrasePattern + #"(?![[:alnum:]])"#

        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }

    private func saveCustomReplacements(_ replacements: [DictionaryReplacement]) {
        guard let data = try? JSONEncoder().encode(replacements) else { return }
        userDefaults.set(data, forKey: customReplacementsKey)
    }

    private func sortedForApplication(_ replacements: [DictionaryReplacement]) -> [DictionaryReplacement] {
        replacements.sorted { lhs, rhs in
            let lhsIsDefault = lhs.category == "default"
            let rhsIsDefault = rhs.category == "default"

            if lhsIsDefault != rhsIsDefault {
                return !lhsIsDefault
            }

            return lhs.heardPhrase.count > rhs.heardPhrase.count
        }
    }

    private func defaultReplacement(
        id: String,
        heardPhrase: String,
        preferredReplacement: String
    ) -> DictionaryReplacement {
        DictionaryReplacement(
            id: UUID(uuidString: id) ?? UUID(),
            heardPhrase: heardPhrase,
            preferredReplacement: preferredReplacement,
            category: "default",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
