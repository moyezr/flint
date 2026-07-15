import Foundation

enum LearningMetric: String, CaseIterable, Sendable {
    case completedUsableDictations = "completed_usable_dictations"
    case teachWordSaves = "teach_word_saves"
    case fixPanelOpens = "fix_panel_opens"
    case fixSaves = "fix_saves"
    case fixCancellations = "fix_cancellations"
    case eligibleMappingsShown = "eligible_mappings_shown"
    case explicitMappingsAccepted = "explicit_mappings_accepted"
    case activeMemoriesApplied = "active_memories_applied"
}

struct LearningMetricsSnapshot: Equatable, Sendable {
    let counts: [LearningMetric: Int]

    static let empty = LearningMetricsSnapshot(counts: [:])

    subscript(_ metric: LearningMetric) -> Int {
        counts[metric, default: 0]
    }

    var plainTextSummary: String {
        LearningMetric.allCases.map { metric in
            "\(metric.rawValue): \(self[metric])"
        }.joined(separator: "\n")
    }
}

actor LearningMetrics {
    nonisolated let storageDescription: String

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "learning.aggregateMetrics.v1"
    ) {
        self.defaults = defaults
        self.key = key
        storageDescription = "UserDefaults key \(key)"
    }

    func increment(_ metric: LearningMetric, by amount: Int = 1) {
        guard amount > 0 else { return }
        var rawCounts = loadRawCounts()
        rawCounts[metric.rawValue, default: 0] += amount
        save(rawCounts)
    }

    func snapshot() -> LearningMetricsSnapshot {
        let rawCounts = loadRawCounts()
        return LearningMetricsSnapshot(counts: Dictionary(
            uniqueKeysWithValues: LearningMetric.allCases.map { metric in
                (metric, max(0, rawCounts[metric.rawValue, default: 0]))
            }
        ))
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }

    private func loadRawCounts() -> [String: Int] {
        guard let data = defaults.data(forKey: key),
              let counts = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return counts
    }

    private func save(_ counts: [String: Int]) {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        defaults.set(data, forKey: key)
    }
}
