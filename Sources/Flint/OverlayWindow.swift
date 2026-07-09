import AppKit
import SwiftUI

enum OverlayState: Equatable {
    case ready
    case listening
    case processingLocally
    case inserting
    case copiedToClipboard
    case cancelled
    case error(String)

    var label: String {
        switch self {
        case .ready:
            return "READY"
        case .listening:
            return "LISTENING"
        case .processingLocally:
            return "PROCESSING LOCALLY"
        case .inserting:
            return "INSERTING"
        case .copiedToClipboard:
            return "COPIED TO CLIPBOARD"
        case .cancelled:
            return "CANCELLED"
        case .error:
            return "ERROR"
        }
    }

    func hint(settings: ShortcutSettings) -> String {
        switch self {
        case .ready:
            return settings.readyHint
        case .listening:
            return settings.listeningHint
        case .processingLocally:
            return "Local transcription"
        case .inserting:
            return "Pasting at cursor"
        case .copiedToClipboard:
            return "Paste manually if needed"
        case .cancelled:
            return "Recording discarded"
        case .error(let message):
            return message
        }
    }

    var isActive: Bool {
        self == .listening || self == .processingLocally || self == .inserting
    }

    var shouldAutoHide: Bool {
        self == .ready || self == .cancelled || self == .copiedToClipboard
    }
}

@MainActor
final class OverlayWindow {
    private let model = OverlayModel()
    private var autoHideCoordinator = OverlayAutoHideCoordinator()
    private let window: NSWindow

    init() {
        let view = OverlayView(model: model)
        window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 92),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = NSHostingView(rootView: view)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.ignoresMouseEvents = true
        window.hasShadow = false
    }

    func show(state: OverlayState) {
        model.state = state
        let visibilityPlan = autoHideCoordinator.show(state)
        positionWindow()
        window.orderFrontRegardless()

        if visibilityPlan.shouldAutoHide {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self,
                      self.autoHideCoordinator.acceptsAutoHide(generation: visibilityPlan.generation) else {
                    return
                }
                self.window.orderOut(nil)
            }
        }
    }

    func setModeLabel(_ label: String) {
        model.modeLabel = label
    }

    func setShortcutSettings(_ settings: ShortcutSettings) {
        model.shortcutSettings = settings
    }

    func updateAudioLevel(_ level: Float) {
        model.audioLevel = min(max(level, 0), 1)
    }

    private func positionWindow() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 56
        )
        window.setFrameOrigin(origin)
    }
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .ready
    @Published var modeLabel: String = "CLEAN"
    @Published var shortcutSettings: ShortcutSettings = .default
    @Published var audioLevel: Float = 0

    var presentation: OverlayPresentation {
        OverlayPresentation(
            state: state,
            modeLabel: modeLabel,
            shortcutSettings: shortcutSettings,
            audioLevel: audioLevel
        )
    }
}

enum OverlayAccent: Equatable {
    case active
    case error
    case inactive
}

struct OverlayPresentation: Equatable {
    let state: OverlayState
    let modeLabel: String
    let shortcutSettings: ShortcutSettings
    let audioLevel: Float

    var label: String {
        state.label
    }

    var hint: String {
        state.hint(settings: shortcutSettings)
    }

    var accent: OverlayAccent {
        if case .error = state {
            return .error
        }
        return state.isActive ? .active : .inactive
    }

    var filledBars: Int {
        switch state {
        case .listening:
            let clampedLevel = min(max(audioLevel, 0), 1)
            guard clampedLevel >= 0.03 else { return 0 }
            return max(1, Int((clampedLevel * 18).rounded(.up)))
        case .processingLocally, .inserting:
            return 14
        case .error:
            return 3
        default:
            return 0
        }
    }
}

struct OverlayVisibilityPlan: Equatable {
    let generation: Int
    let shouldAutoHide: Bool
}

struct OverlayAutoHideCoordinator {
    private(set) var generation = 0

    mutating func show(_ state: OverlayState) -> OverlayVisibilityPlan {
        generation += 1
        return OverlayVisibilityPlan(generation: generation, shouldAutoHide: state.shouldAutoHide)
    }

    func acceptsAutoHide(generation requestedGeneration: Int) -> Bool {
        generation == requestedGeneration
    }
}

struct OverlayView: View {
    @ObservedObject var model: OverlayModel

    private let orange = Color(red: 1.0, green: 0.416, blue: 0.0)
    private let red = Color(red: 0.9, green: 0.18, blue: 0.16)

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(accentColor)
                    .frame(width: 8, height: 8)
                Text(model.presentation.label)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.primary)
                Spacer()
                Text(model.modeLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.secondary)
            }

            levelMeter

            Text(model.presentation.hint)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.leading, 12)
        .padding(.trailing, 12)
        .padding(.vertical, 10)
        .frame(width: 300, height: 92)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 3)
        }
        .overlay {
            Rectangle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
    }

    private var accentColor: Color {
        switch model.presentation.accent {
        case .active:
            return orange
        case .error:
            return red
        case .inactive:
            return Color.secondary
        }
    }

    private var levelMeter: some View {
        HStack(spacing: 3) {
            ForEach(0..<18, id: \.self) { index in
                Rectangle()
                    .fill(index < model.presentation.filledBars ? orange : Color(nsColor: .separatorColor))
                    .frame(width: 10, height: 9)
            }
        }
        .frame(height: 10)
    }
}
