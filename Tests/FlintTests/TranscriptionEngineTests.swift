import XCTest
@testable import Flint

final class TranscriptionEngineTests: XCTestCase {
    func testMissingAudioFileThrowsBeforeTranscription() async {
        let engine = TranscriptionEngine()
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-missing-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        await XCTAssertThrowsErrorAsync(try await engine.transcribe(audioFileURL: missingURL)) { error in
            guard case TranscriptionEngine.TranscriptionError.audioFileMissing(missingURL) = error else {
                return XCTFail("Expected audioFileMissing, got \(error)")
            }
        }
    }

    func testEmptyAudioFileThrowsBeforeTranscription() async throws {
        let engine = TranscriptionEngine()
        let emptyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-empty-\(UUID().uuidString)")
            .appendingPathExtension("m4a")
        FileManager.default.createFile(atPath: emptyURL.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: emptyURL) }

        await XCTAssertThrowsErrorAsync(try await engine.transcribe(audioFileURL: emptyURL)) { error in
            guard case TranscriptionEngine.TranscriptionError.audioFileEmpty(emptyURL) = error else {
                return XCTFail("Expected audioFileEmpty, got \(error)")
            }
        }
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ errorHandler: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown.", file: file, line: line)
    } catch {
        errorHandler(error)
    }
}
