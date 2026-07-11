import AppKit

enum DictationFeedbackEvent {
    case started
    case stopped
    case inserted
    case cancelled
    case failed
}

enum DictationFeedbackSound: Equatable {
    case started
    case stopped
}

enum DictationHaptic: Equatable {
    case started
    case completed
    case cancelled
    case failed
}

struct DictationFeedback {
    private let soundPlayer: (DictationFeedbackSound) -> Void
    private let hapticPerformer: (DictationHaptic) -> Void
    private let errorBeep: () -> Void

    init(
        soundPlayer: @escaping (DictationFeedbackSound) -> Void = DictationFeedback.play,
        hapticPerformer: @escaping (DictationHaptic) -> Void = DictationFeedback.perform,
        errorBeep: @escaping () -> Void = NSSound.beep
    ) {
        self.soundPlayer = soundPlayer
        self.hapticPerformer = hapticPerformer
        self.errorBeep = errorBeep
    }

    @MainActor
    func perform(_ event: DictationFeedbackEvent, settings: AppSettings) {
        switch event {
        case .started:
            hapticPerformer(.started)
            if settings.playStartSound {
                soundPlayer(.started)
            }
        case .stopped:
            if settings.playStopSound {
                soundPlayer(.stopped)
            }
        case .inserted:
            hapticPerformer(.completed)
        case .cancelled:
            hapticPerformer(.cancelled)
        case .failed:
            hapticPerformer(.failed)
            errorBeep()
        }
    }

    private static func play(_ sound: DictationFeedbackSound) {
        let name: NSSound.Name
        switch sound {
        case .started:
            name = NSSound.Name("Tink")
        case .stopped:
            name = NSSound.Name("Pop")
        }
        NSSound(named: name)?.play()
    }

    private static func perform(_ haptic: DictationHaptic) {
        let pattern: NSHapticFeedbackManager.FeedbackPattern
        switch haptic {
        case .started:
            pattern = .alignment
        case .completed:
            pattern = .levelChange
        case .cancelled, .failed:
            pattern = .generic
        }
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }
}
