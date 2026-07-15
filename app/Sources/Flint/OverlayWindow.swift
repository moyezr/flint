import AppKit
import SwiftUI

enum OverlayState: Equatable {
    case ready
    case preparingModel
    case listening
    case processingLocally
    case inserting
    case inserted
    case copiedToClipboard
    case cancelled
    case error(String)

    var label: String {
        switch self {
        case .ready:
            return "READY"
        case .preparingModel:
            return "PREPARING MODEL"
        case .listening:
            return "LISTENING"
        case .processingLocally:
            return "PROCESSING"
        case .inserting:
            return "INSERTING"
        case .inserted:
            return "INSERTED"
        case .copiedToClipboard:
            return "COPIED"
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
        case .preparingModel:
            return "First launch can take a moment"
        case .listening:
            return settings.listeningHint
        case .processingLocally:
            return "Turning speech into text"
        case .inserting:
            return "Pasting at cursor"
        case .inserted:
            return "Inserted at cursor"
        case .copiedToClipboard:
            return "Paste manually if needed"
        case .cancelled:
            return "Recording discarded"
        case .error(let message):
            return message
        }
    }

    var isActive: Bool {
        self == .preparingModel || self == .listening || self == .processingLocally || self == .inserting
    }

    var showsActions: Bool {
        self == .inserted || self == .copiedToClipboard
    }

    var autoHideDelay: TimeInterval? {
        switch self {
        case .ready, .cancelled:
            return 1.5
        case .inserted, .copiedToClipboard:
            return 6
        default:
            return nil
        }
    }

    var shouldAutoHide: Bool { autoHideDelay != nil }
}

@MainActor
final class OverlayWindow {
    private let model = OverlayModel()
    private var autoHideCoordinator = OverlayAutoHideCoordinator()
    private let window: NSPanel

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
        window.level = .statusBar
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.animationBehavior = .none
        window.becomesKeyOnlyIfNeeded = true
    }

    func configureActions(
        onFix: @escaping @MainActor () -> Void,
        onTeach: @escaping @MainActor () -> Void
    ) {
        model.onFix = onFix
        model.onTeach = onTeach
    }

    func show(state: OverlayState) {
        withAnimation(.snappy(duration: 0.32, extraBounce: 0.08)) {
            model.state = state
        }

        let visibilityPlan = autoHideCoordinator.show(state)
        window.ignoresMouseEvents = !state.showsActions
        animateWindow(to: state)
        window.orderFrontRegardless()

        if let delay = state.autoHideDelay {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
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

    private func animateWindow(to state: OverlayState) {
        guard let screen = preferredScreen() else { return }
        let targetFrame = OverlayLayout.frame(on: screen.frame, for: state)
        if !window.isVisible {
            window.setFrame(targetFrame, display: true)
            return
        }

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    private func preferredScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) ?? NSScreen.main
    }
}

enum OverlayLayout {
    static let compactSize = CGSize(width: 142, height: 42)
    static let listeningSize = CGSize(width: 224, height: 62)
    static let activitySize = CGSize(width: 208, height: 58)
    static let completedSize = CGSize(width: 326, height: 72)
    static let errorSize = CGSize(width: 330, height: 82)
    static let meterBarCount = 9

    static func size(for state: OverlayState) -> CGSize {
        switch state {
        case .ready, .cancelled:
            return compactSize
        case .listening:
            return listeningSize
        case .preparingModel, .processingLocally, .inserting:
            return activitySize
        case .inserted, .copiedToClipboard:
            return completedSize
        case .error:
            return errorSize
        }
    }

    static func frame(on screenFrame: CGRect, for state: OverlayState) -> CGRect {
        let size = size(for: state)
        return CGRect(
            x: screenFrame.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .ready
    @Published var audioLevel: Float = 0

    var onFix: @MainActor () -> Void = {}
    var onTeach: @MainActor () -> Void = {}

    var presentation: OverlayPresentation {
        OverlayPresentation(state: state, audioLevel: audioLevel)
    }
}

enum OverlayAccent: Equatable {
    case active
    case success
    case error
    case inactive
}

struct OverlayPresentation: Equatable {
    let state: OverlayState
    let audioLevel: Float

    var accent: OverlayAccent {
        if case .error = state { return .error }
        if state == .inserted || state == .copiedToClipboard { return .success }
        return state.isActive ? .active : .inactive
    }

    var filledBars: Int {
        switch state {
        case .listening:
            let clampedLevel = min(max(audioLevel, 0), 1)
            guard clampedLevel >= 0.03 else { return 0 }
            return max(1, Int((clampedLevel * Float(OverlayLayout.meterBarCount)).rounded(.up)))
        case .preparingModel, .processingLocally, .inserting:
            return OverlayLayout.meterBarCount
        case .error:
            return 3
        default:
            return 0
        }
    }

    var usesActivityPulse: Bool {
        state == .preparingModel || state == .processingLocally || state == .inserting
    }

    func isMeterBarActive(_ index: Int, animationPhase: Int) -> Bool {
        guard (0..<OverlayLayout.meterBarCount).contains(index) else { return false }
        switch state {
        case .preparingModel, .processingLocally, .inserting:
            let pulseWidth = 4
            let travelDistance = OverlayLayout.meterBarCount + pulseWidth
            let start = animationPhase % travelDistance - pulseWidth
            return (start..<(start + pulseWidth)).contains(index)
        default:
            return index < filledBars
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
    private let green = Color(red: 0.28, green: 0.82, blue: 0.48)
    private let red = Color(red: 1.0, green: 0.28, blue: 0.25)

    var body: some View {
        stateContent
            .frame(
                width: OverlayLayout.size(for: model.state).width,
                height: OverlayLayout.size(for: model.state).height,
                alignment: .bottom
            )
            .background(Color.black)
            .clipShape(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: 22,
                    bottomTrailingRadius: 22
                )
            )
            .overlay {
                UnevenRoundedRectangle(
                    bottomLeadingRadius: 22,
                    bottomTrailingRadius: 22
                )
                .strokeBorder(accentColor.opacity(model.state.isActive ? 0.42 : 0.18), lineWidth: 1)
            }
            .shadow(color: accentColor.opacity(model.state.isActive ? 0.25 : 0.1), radius: 18, y: 8)
            .animation(.snappy(duration: 0.3, extraBounce: 0.08), value: model.state)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch model.state {
        case .ready:
            compactStatus(icon: "waveform", title: "Flint", color: orange)
        case .cancelled:
            compactStatus(icon: "xmark", title: "Cancelled", color: .secondary)
        case .listening:
            HStack(spacing: 12) {
                listeningOrb
                VStack(alignment: .leading, spacing: 4) {
                    Text("Listening")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    levelMeter
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        case .preparingModel, .processingLocally, .inserting:
            HStack(spacing: 11) {
                ProgressView()
                    .controlSize(.small)
                    .tint(orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(activityTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    activityMeter
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 10)
        case .inserted, .copiedToClipboard:
            HStack(spacing: 10) {
                Image(systemName: model.state == .inserted ? "checkmark.circle.fill" : "doc.on.clipboard.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(green)
                Text(model.state == .inserted ? "Inserted" : "Copied")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer(minLength: 2)
                actionButton("Fix", systemImage: "pencil", action: model.onFix)
                actionButton("Teach", systemImage: "plus", action: model.onTeach)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        case .error(let message):
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(red)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Something went wrong")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(message)
                        .font(.system(size: 10))
                        .foregroundStyle(.white.opacity(0.68))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 11)
        }
    }

    private func compactStatus(icon: String, title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .padding(.bottom, 9)
    }

    private var listeningOrb: some View {
        ZStack {
            Circle()
                .fill(orange.opacity(0.15))
                .frame(width: 30, height: 30)
                .scaleEffect(1 + CGFloat(model.audioLevel) * 0.16)
            Circle()
                .fill(orange)
                .frame(width: 10, height: 10)
                .shadow(color: orange.opacity(0.8), radius: 7)
        }
    }

    private var levelMeter: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<OverlayLayout.meterBarCount, id: \.self) { index in
                let normalizedIndex = Float(index + 1) / Float(OverlayLayout.meterBarCount)
                Capsule()
                    .fill(index < model.presentation.filledBars ? orange : Color.white.opacity(0.14))
                    .frame(width: 4, height: 5 + CGFloat(normalizedIndex * max(model.audioLevel, 0.12)) * 12)
            }
        }
        .frame(height: 18)
    }

    private var activityMeter: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 12.0)) { context in
            let phase = Int(context.date.timeIntervalSinceReferenceDate * 12)
            HStack(spacing: 3) {
                ForEach(0..<OverlayLayout.meterBarCount, id: \.self) { index in
                    Capsule()
                        .fill(
                            model.presentation.isMeterBarActive(index, animationPhase: phase)
                                ? orange
                                : Color.white.opacity(0.14)
                        )
                        .frame(width: 9, height: 4)
                }
            }
        }
    }

    private var activityTitle: String {
        switch model.state {
        case .preparingModel:
            return "Preparing Flint"
        case .inserting:
            return "Inserting"
        default:
            return "Processing"
        }
    }

    private func actionButton(
        _ title: String,
        systemImage: String,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var accentColor: Color {
        switch model.presentation.accent {
        case .active:
            return orange
        case .success:
            return green
        case .error:
            return red
        case .inactive:
            return Color.white.opacity(0.4)
        }
    }
}
