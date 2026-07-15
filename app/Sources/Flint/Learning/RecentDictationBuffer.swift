import Foundation

struct RecentDictation: Identifiable, Equatable, Sendable {
    let id: UUID
    let createdAt: Date
    let rawText: String
    let insertedText: String
    let applicationName: String?
    let applicationBundleID: String?
    let language: String
    let cleanupMode: CleanupMode
    let deliveryResult: TextInsertionResult

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rawText: String,
        insertedText: String,
        applicationName: String?,
        applicationBundleID: String?,
        language: String,
        cleanupMode: CleanupMode,
        deliveryResult: TextInsertionResult
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rawText = rawText
        self.insertedText = insertedText
        self.applicationName = applicationName
        self.applicationBundleID = applicationBundleID
        self.language = language
        self.cleanupMode = cleanupMode
        self.deliveryResult = deliveryResult
    }
}

struct RecentDictationBuffer: Equatable, Sendable {
    static let capacity = 10

    private(set) var entries: [RecentDictation] = []

    var isEmpty: Bool { entries.isEmpty }
    var newestFirst: [RecentDictation] { Array(entries.reversed()) }

    mutating func append(_ dictation: RecentDictation) {
        entries.append(dictation)
        if entries.count > Self.capacity {
            entries.removeFirst(entries.count - Self.capacity)
        }
    }

    mutating func removeAll() {
        entries.removeAll(keepingCapacity: false)
    }
}
