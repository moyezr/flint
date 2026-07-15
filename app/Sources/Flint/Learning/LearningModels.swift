import Foundation

enum LearningMemoryType: String, Codable, Sendable {
    case vocabulary
}

enum LearningScopeKind: String, Codable, CaseIterable, Sendable {
    case global
    case application
}

enum LearningMemoryStatus: String, Codable, CaseIterable, Sendable {
    case proposed
    case active
    case disabled
    case rejected
}

enum LearningMemoryOrigin: String, Codable, Sendable {
    case seeded
    case explicitCorrection = "explicit_correction"
}

enum CorrectionEvidenceSource: String, Codable, Sendable {
    case explicitFix = "explicit_fix"
}

struct LearningMemory: Identifiable, Equatable, Sendable {
    let id: UUID
    let memoryType: LearningMemoryType
    let scopeKind: LearningScopeKind
    let scopeValue: String
    let language: String
    let heardForm: String
    let heardKey: String
    let preferredForm: String
    let confidence: Double
    let evidenceCount: Int
    let usageCount: Int
    let status: LearningMemoryStatus
    let origin: LearningMemoryOrigin
    let createdAt: Date
    let updatedAt: Date
    let lastUsedAt: Date?
}

struct LearningMemoryDraft: Equatable, Sendable {
    var heardForm: String
    var preferredForm: String
    var scopeKind: LearningScopeKind = .global
    var scopeValue: String = ""
    var language: String = "auto"
    var status: LearningMemoryStatus = .active
    var origin: LearningMemoryOrigin = .seeded
    var confidence: Double = 1
    var evidenceCount: Int = 1

    var normalized: LearningMemoryDraft {
        var copy = self
        copy.heardForm = heardForm.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.preferredForm = preferredForm.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.scopeValue = scopeKind == .global
            ? ""
            : scopeValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLanguage = language.trimmingCharacters(in: .whitespacesAndNewlines)
        copy.language = trimmedLanguage.isEmpty ? "auto" : trimmedLanguage
        return copy
    }
}

struct CorrectionEvidence: Identifiable, Equatable, Sendable {
    let id: UUID
    let memoryItemID: UUID?
    let originalText: String
    let correctedText: String
    let applicationBundleID: String
    let language: String
    let cleanupMode: CleanupMode?
    let source: CorrectionEvidenceSource
    let createdAt: Date
}

struct CorrectionEvidenceDraft: Equatable, Sendable {
    var originalText: String
    var correctedText: String
    var applicationBundleID: String = ""
    var language: String = "auto"
    var cleanupMode: CleanupMode?
    var source: CorrectionEvidenceSource = .explicitFix
    var createdAt: Date = Date()
}

struct ExplicitCorrectionWrite: Equatable, Sendable {
    var memory: LearningMemoryDraft?
    var evidence: CorrectionEvidenceDraft
}

struct ExplicitCorrectionWriteResult: Equatable, Sendable {
    let memory: LearningMemory?
    let evidence: CorrectionEvidence
}

struct LearningStoreSummary: Equatable, Sendable {
    let activeMemoryCount: Int
    let evidenceCount: Int
    let databaseSizeBytes: Int64
}

enum VocabularyNormalizer {
    static func key(for phrase: String) -> String {
        let collapsed = phrase
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")

        return collapsed.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
    }
}
