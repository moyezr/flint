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

    func testUserFacingMessageMapsMissingAndEmptyAudioToNoUsableAudio() {
        let missingError = TranscriptionEngine.TranscriptionError.audioFileMissing(URL(fileURLWithPath: "/tmp/missing.m4a"))
        let emptyError = TranscriptionEngine.TranscriptionError.audioFileEmpty(URL(fileURLWithPath: "/tmp/empty.m4a"))

        XCTAssertEqual(TranscriptionEngine.userFacingMessage(for: missingError), "No usable audio was captured.")
        XCTAssertEqual(TranscriptionEngine.userFacingMessage(for: emptyError), "No usable audio was captured.")
    }

    func testUserFacingMessageMapsEmptyTranscriptToNoSpeechDetected() {
        XCTAssertEqual(
            TranscriptionEngine.userFacingMessage(for: TranscriptionEngine.TranscriptionError.emptyTranscript),
            "No speech detected."
        )
    }

    func testUserFacingMessageMapsGenericTranscriptionFailure() {
        XCTAssertEqual(
            TranscriptionEngine.userFacingMessage(for: NSError(domain: "WhisperKit", code: 1)),
            "Local transcription failed."
        )
    }

    func testDictationOutputPolicyRejectsEmptyOutput() {
        XCTAssertNil(DictationOutputPolicy.usableOutput(from: " \n\t "))
        XCTAssertEqual(DictationOutputPolicy.emptyOutputMessage, "No speech detected.")
    }

    func testDictationOutputPolicyTrimsUsableOutput() {
        XCTAssertEqual(DictationOutputPolicy.usableOutput(from: "  hello world\n"), "hello world")
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
