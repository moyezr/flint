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
            return "PROCESSING"
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
            return "Transcribing"
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
            contentRect: NSRect(origin: .zero, size: OverlayLayout.size(for: .ready)),
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
        withAnimation(.easeOut(duration: 0.12)) {
            model.state = state
        }
        window.setContentSize(OverlayLayout.size(for: state))
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

    func updateAudioLevel(_ level: Float) {
        withAnimation(.linear(duration: 0.05)) {
            model.audioLevel = min(max(level, 0), 1)
        }
    }

    private func positionWindow() {
        guard let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        let size = window.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 36
        )
        window.setFrameOrigin(origin)
    }
}

enum OverlayLayout {
    static let compactSize = CGSize(width: 124, height: 32)
    static let errorSize = CGSize(width: 230, height: 68)
    static let meterBarCount = 12

    static func size(for state: OverlayState) -> CGSize {
        if case .error = state {
            return errorSize
        }
        return compactSize
    }
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .ready
    @Published var audioLevel: Float = 0

    var presentation: OverlayPresentation {
        OverlayPresentation(
            state: state,
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
    let audioLevel: Float

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
            return max(1, Int((clampedLevel * Float(OverlayLayout.meterBarCount)).rounded(.up)))
        case .processingLocally, .inserting:
            return OverlayLayout.meterBarCount
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
        Group {
            if case .error = model.state {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 7) {
                        Circle()
                            .fill(accentColor)
                            .frame(width: 7, height: 7)
                        Text("ERROR")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.primary)
                    }
                    Text(model.state.hint(settings: .default))
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            } else {
                HStack(spacing: 8) {
                    Circle()
                        .fill(accentColor)
                        .frame(width: 6, height: 6)
                    levelMeter
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .frame(
            width: OverlayLayout.size(for: model.state).width,
            height: OverlayLayout.size(for: model.state).height
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(accentColor)
                .frame(width: 2)
        }
        .overlay {
            Rectangle()
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .animation(.easeOut(duration: 0.12), value: model.state)
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
        HStack(spacing: 2) {
            ForEach(0..<OverlayLayout.meterBarCount, id: \.self) { index in
                Rectangle()
                    .fill(index < model.presentation.filledBars ? orange : Color(nsColor: .separatorColor))
                    .frame(width: 5, height: 8)
            }
        }
        .frame(height: 8)
    }
}
