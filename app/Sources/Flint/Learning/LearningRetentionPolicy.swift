import Foundation

struct LearningRetentionPolicy: Equatable, Sendable {
    var evidenceMaxAge: TimeInterval
    var evidenceMaxCount: Int
    var databaseHighWaterBytes: Int64

    static let `default` = LearningRetentionPolicy(
        evidenceMaxAge: 90 * 24 * 60 * 60,
        evidenceMaxCount: 2_000,
        databaseHighWaterBytes: 50 * 1_024 * 1_024
    )

    func evidenceCutoffDate(relativeTo now: Date) -> Date {
        now.addingTimeInterval(-max(0, evidenceMaxAge))
    }
}
