import Foundation

struct MemorySnapshot: Equatable, Sendable {
    static let empty = MemorySnapshot(memories: [])

    let memories: [LearningMemory]

    init(memories: [LearningMemory]) {
        self.memories = memories
            .filter { $0.memoryType == .vocabulary && $0.status == .active }
            .sorted(by: Self.applicationOrder)
    }

    func vocabulary(language: String, applicationBundleID: String?) -> [LearningMemory] {
        let normalizedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestedLanguage = normalizedLanguage.isEmpty ? "auto" : normalizedLanguage

        let candidates = memories.filter { memory in
            let languageMatches = memory.language == "auto" || memory.language == requestedLanguage
            guard languageMatches else { return false }

            switch memory.scopeKind {
            case .global:
                return true
            case .application:
                return !memory.scopeValue.isEmpty && memory.scopeValue == applicationBundleID
            }
        }

        var seenKeys: Set<String> = []
        return candidates
            .sorted { lhs, rhs in
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
            .filter { memory in
                seenKeys.insert(memory.heardKey).inserted
            }
    }

    private static func applicationOrder(_ lhs: LearningMemory, _ rhs: LearningMemory) -> Bool {
        if lhs.scopeKind != rhs.scopeKind {
            return lhs.scopeKind == .application
        }
        if lhs.heardKey.count != rhs.heardKey.count {
            return lhs.heardKey.count > rhs.heardKey.count
        }
        return lhs.updatedAt > rhs.updatedAt
    }
}
