import AVFoundation
import Foundation

final class AudioRecorder: NSObject, AVAudioRecorderDelegate {
    enum RecorderError: LocalizedError {
        case microphonePermissionDenied
        case recorderDidNotStart
        case notRecording

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone permission is required."
            case .recorderDidNotStart:
                return "The audio recorder did not start."
            case .notRecording:
                return "No active recording exists."
            }
        }
    }

    private var recorder: AVAudioRecorder?
    private var currentURL: URL?

    func start() async throws {
        guard await requestMicrophoneAccess() else {
            throw RecorderError.microphonePermissionDenied
        }

        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("flint-\(UUID().uuidString)")
            .appendingPathExtension("m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        let recorder = try AVAudioRecorder(url: audioURL, settings: settings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        guard recorder.record() else {
            throw RecorderError.recorderDidNotStart
        }

        self.recorder = recorder
        currentURL = audioURL
    }

    func stop() throws -> URL {
        guard let recorder, let currentURL else {
            throw RecorderError.notRecording
        }

        recorder.stop()
        self.recorder = nil
        self.currentURL = nil
        return currentURL
    }

    private func requestMicrophoneAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}
