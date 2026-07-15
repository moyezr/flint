import XCTest
@testable import Flint

final class RecentDictationBufferTests: XCTestCase {
    func testCapacityIsTenAndOldestEntryIsEvicted() {
        var buffer = RecentDictationBuffer()
        let entries = (0..<11).map(makeEntry)
        entries.forEach { buffer.append($0) }

        XCTAssertEqual(buffer.entries.count, 10)
        XCTAssertEqual(buffer.entries.first?.id, entries[1].id)
        XCTAssertEqual(buffer.entries.last?.id, entries[10].id)
        XCTAssertEqual(buffer.newestFirst.first?.id, entries[10].id)
    }

    func testFrozenEntryTextAndClipboardDeliveryAreRetainedInMemory() {
        var buffer = RecentDictationBuffer()
        let entry = RecentDictation(
            rawText: "post grass",
            insertedText: "Post grass.",
            applicationName: "Notes",
            applicationBundleID: "com.apple.Notes",
            language: "en",
            cleanupMode: .clean,
            deliveryResult: .copiedToClipboard
        )
        buffer.append(entry)

        XCTAssertEqual(buffer.entries, [entry])
        XCTAssertEqual(buffer.entries.first?.insertedText, "Post grass.")
        XCTAssertEqual(buffer.entries.first?.deliveryResult, .copiedToClipboard)
    }

    func testRemoveAllClearsBuffer() {
        var buffer = RecentDictationBuffer()
        buffer.append(makeEntry(0))
        buffer.removeAll()
        XCTAssertTrue(buffer.isEmpty)
    }

    private func makeEntry(_ index: Int) -> RecentDictation {
        RecentDictation(
            createdAt: Date(timeIntervalSince1970: Double(index)),
            rawText: "raw \(index)",
            insertedText: "final \(index)",
            applicationName: nil,
            applicationBundleID: nil,
            language: "auto",
            cleanupMode: .clean,
            deliveryResult: .inserted
        )
    }
}
