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
        let screen = preferredScreen()
        let screenGeometry = screen.map(OverlayLayout.screenGeometry(for:))
        withAnimation(.snappy(duration: 0.32, extraBounce: 0.08)) {
            model.notchWidth = screenGeometry?.notchWidth ?? 0
            model.reservesHardwareNotch = screenGeometry?.hasHardwareNotch ?? false
            model.state = state
        }

        let visibilityPlan = autoHideCoordinator.show(state)
        window.ignoresMouseEvents = !state.showsActions
        animateWindow(to: state, on: screen, geometry: screenGeometry)
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

    private func animateWindow(
        to state: OverlayState,
        on screen: NSScreen?,
        geometry: OverlayScreenGeometry?
    ) {
        guard let screen else { return }
        let targetFrame = OverlayLayout.frame(
            on: screen.frame,
            for: state,
            geometry: geometry
        )
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

struct OverlayScreenGeometry: Equatable {
    let screenFrame: CGRect
    let notchMinX: CGFloat
    let notchWidth: CGFloat
    let hasHardwareNotch: Bool

    var notchMaxX: CGFloat { notchMinX + notchWidth }
}

struct OverlayWingWidths: Equatable {
    let left: CGFloat
    let right: CGFloat
}

enum OverlayLayout {
    static let defaultNotchWidth: CGFloat = 142
    static let islandHeight: CGFloat = 42
    static let compactSize = CGSize(width: defaultNotchWidth, height: islandHeight)
    static let statusWingWidth: CGFloat = 42
    static let activityWingWidth: CGFloat = 104
    static let completedActionsWingWidth: CGFloat = 136
    static let errorStatusWingWidth: CGFloat = 36
    static let minimumErrorMessageWingWidth: CGFloat = 132
    static let maximumErrorMessageWingWidth: CGFloat = 250
    static let meterBarCount = 9

    static var listeningSize: CGSize { size(for: .listening) }
    static var activitySize: CGSize { size(for: .processingLocally) }
    static var completedSize: CGSize { size(for: .inserted) }

    static func wingWidths(for state: OverlayState) -> OverlayWingWidths {
        switch state {
        case .ready, .cancelled:
            if state == .cancelled {
                return OverlayWingWidths(left: statusWingWidth, right: 78)
            }
            return OverlayWingWidths(left: 0, right: 0)
        case .listening:
            return OverlayWingWidths(left: statusWingWidth, right: activityWingWidth)
        case .preparingModel, .processingLocally, .inserting:
            return OverlayWingWidths(left: statusWingWidth, right: activityWingWidth)
        case .inserted, .copiedToClipboard:
            return OverlayWingWidths(left: statusWingWidth, right: completedActionsWingWidth)
        case .error(let message):
            return OverlayWingWidths(
                left: errorStatusWingWidth,
                right: errorMessageWingWidth(for: message)
            )
        }
    }

    static func size(
        for state: OverlayState,
        notchWidth: CGFloat = 0,
        reservesHardwareNotch: Bool = false
    ) -> CGSize {
        let wings = wingWidths(for: state)
        let centerWidth = centerWidth(
            for: state,
            notchWidth: notchWidth,
            reservesHardwareNotch: reservesHardwareNotch
        )
        return CGSize(
            width: centerWidth + wings.left + wings.right,
            height: islandHeight
        )
    }

    static func centerWidth(
        for state: OverlayState,
        notchWidth: CGFloat,
        reservesHardwareNotch: Bool
    ) -> CGFloat {
        if reservesHardwareNotch {
            return max(notchWidth, 0)
        }
        return state == .ready ? defaultNotchWidth : 0
    }

    static func errorMessageWingWidth(for message: String) -> CGFloat {
        let estimatedTextWidth = CGFloat(message.count) * 5.7 + 22
        return min(
            max(estimatedTextWidth.rounded(.up), minimumErrorMessageWingWidth),
            maximumErrorMessageWingWidth
        )
    }

    static func screenGeometry(for screen: NSScreen) -> OverlayScreenGeometry {
        screenGeometry(
            screenFrame: screen.frame,
            auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
            auxiliaryTopRightArea: screen.auxiliaryTopRightArea
        )
    }

    static func screenGeometry(
        screenFrame: CGRect,
        auxiliaryTopLeftArea: CGRect?,
        auxiliaryTopRightArea: CGRect?
    ) -> OverlayScreenGeometry {
        if let leftArea = auxiliaryTopLeftArea,
           let rightArea = auxiliaryTopRightArea,
           !leftArea.isEmpty,
           !rightArea.isEmpty,
           leftArea.maxX < rightArea.minX {
            return OverlayScreenGeometry(
                screenFrame: screenFrame,
                notchMinX: leftArea.maxX,
                notchWidth: rightArea.minX - leftArea.maxX,
                hasHardwareNotch: true
            )
        }

        return OverlayScreenGeometry(
            screenFrame: screenFrame,
            notchMinX: screenFrame.midX,
            notchWidth: 0,
            hasHardwareNotch: false
        )
    }

    static func frame(
        on screenFrame: CGRect,
        for state: OverlayState,
        geometry: OverlayScreenGeometry? = nil
    ) -> CGRect {
        let geometry = geometry ?? screenGeometry(
            screenFrame: screenFrame,
            auxiliaryTopLeftArea: nil,
            auxiliaryTopRightArea: nil
        )
        let wings = wingWidths(for: state)
        let size = size(
            for: state,
            notchWidth: geometry.notchWidth,
            reservesHardwareNotch: geometry.hasHardwareNotch
        )
        let originX = geometry.hasHardwareNotch
            ? geometry.notchMinX - wings.left
            : screenFrame.midX - size.width / 2
        return CGRect(
            x: originX,
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
    @Published var notchWidth: CGFloat = 0
    @Published var reservesHardwareNotch = false

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
                width: islandSize.width,
                height: islandSize.height
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
            .animation(.snappy(duration: 0.3, extraBounce: 0.08), value: model.notchWidth)
            .animation(.snappy(duration: 0.3, extraBounce: 0.08), value: model.reservesHardwareNotch)
    }

    private var islandSize: CGSize {
        OverlayLayout.size(
            for: model.state,
            notchWidth: model.notchWidth,
            reservesHardwareNotch: model.reservesHardwareNotch
        )
    }

    private var stateContent: some View {
        let wings = OverlayLayout.wingWidths(for: model.state)
        let centerWidth = OverlayLayout.centerWidth(
            for: model.state,
            notchWidth: model.notchWidth,
            reservesHardwareNotch: model.reservesHardwareNotch
        )
        return HStack(spacing: 0) {
            leftAccessory
                .frame(width: wings.left, height: OverlayLayout.islandHeight)

            centerNotchContent
                .frame(width: centerWidth, height: OverlayLayout.islandHeight)

            rightAccessory
                .frame(width: wings.right, height: OverlayLayout.islandHeight)
        }
    }

    @ViewBuilder
    private var leftAccessory: some View {
        switch model.state {
        case .ready:
            EmptyView()
        case .cancelled:
            statusIcon("xmark", color: .secondary)
        case .listening:
            pulsingDot(audioReactive: true)
        case .preparingModel, .processingLocally, .inserting:
            pulsingDot(audioReactive: false)
        case .inserted, .copiedToClipboard:
            statusIcon(
                model.state == .inserted ? "checkmark.circle.fill" : "doc.on.clipboard.fill",
                color: green,
                size: 17
            )
        case .error:
            statusIcon("exclamationmark.triangle.fill", color: red)
        }
    }

    @ViewBuilder
    private var centerNotchContent: some View {
        if model.state == .ready {
            compactStatus(icon: "waveform", title: "Flint", color: orange)
        } else {
            Color.clear
        }
    }

    @ViewBuilder
    private var rightAccessory: some View {
        switch model.state {
        case .ready:
            EmptyView()
        case .cancelled:
            Text("Cancelled")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.72))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 7)
        case .listening:
            levelMeter
        case .preparingModel, .processingLocally, .inserting:
            activityMeter
        case .inserted, .copiedToClipboard:
            HStack(spacing: 7) {
                actionButton("Fix", systemImage: "pencil", action: model.onFix)
                actionButton("Teach", systemImage: "plus", action: model.onTeach)
            }
            .padding(.trailing, 9)
        case .error(let message):
            Text(message)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.82))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 7)
                .padding(.trailing, 12)
        }
    }

    private func statusIcon(_ name: String, color: Color, size: CGFloat = 12) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(color)
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
    }

    private func pulsingDot(audioReactive: Bool) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate * 2.4
            let pulse = (sin(phase * .pi) + 1) / 2
            let audioBoost = audioReactive ? Double(model.audioLevel) * 0.12 : 0

            ZStack {
                Circle()
                    .fill(orange.opacity(0.12 + pulse * 0.12))
                    .frame(width: 21, height: 21)
                    .scaleEffect(0.88 + pulse * 0.18 + audioBoost)
                Circle()
                    .fill(orange)
                    .frame(width: 7, height: 7)
                    .shadow(color: orange.opacity(0.65 + pulse * 0.25), radius: 4 + pulse * 3)
            }
            .frame(width: 22, height: 22)
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
