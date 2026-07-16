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

        if let delay = state.autoHideDelay {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self,
                      self.autoHideCoordinator.acceptsAutoHide(generation: visibilityPlan.generation) else {
                    return
                }
                self.animateWindowOut(generation: visibilityPlan.generation)
            }
        }
    }

    func updateAudioLevel(_ level: Float) {
        withAnimation(.easeOut(duration: 0.09)) {
            model.updateAudioLevel(level)
        }
    }

    func resetAudioLevel() {
        model.resetAudioLevel()
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
            window.alphaValue = 0
            window.setFrame(OverlayMotion.hiddenFrame(from: targetFrame), display: true)
            window.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = OverlayMotion.appearanceDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                window.animator().alphaValue = 1
                window.animator().setFrame(targetFrame, display: true)
            }
            return
        }

        window.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().alphaValue = 1
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    private func animateWindowOut(generation: Int) {
        guard window.isVisible,
              autoHideCoordinator.acceptsAutoHide(generation: generation) else {
            return
        }

        let hiddenFrame = OverlayMotion.hiddenFrame(from: window.frame)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = OverlayMotion.disappearanceDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 0
            window.animator().setFrame(hiddenFrame, display: true)
        } completionHandler: { [weak self] in
            DispatchQueue.main.async {
                guard let self,
                      self.autoHideCoordinator.acceptsAutoHide(generation: generation) else {
                    return
                }
                self.window.orderOut(nil)
            }
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

enum OverlayMotion {
    static let appearanceDuration: TimeInterval = 0.24
    static let disappearanceDuration: TimeInterval = 0.2
    static let verticalOffset: CGFloat = 5

    static func hiddenFrame(from visibleFrame: CGRect) -> CGRect {
        visibleFrame.offsetBy(dx: 0, dy: verticalOffset)
    }
}

enum OverlayLayout {
    static let defaultNotchWidth: CGFloat = 142
    static let islandHeight: CGFloat = 42
    static let compactSize = CGSize(width: defaultNotchWidth, height: islandHeight)
    static let statusWingWidth: CGFloat = 42
    static let waveformWingWidth: CGFloat = 58
    static let spinnerWingWidth: CGFloat = 38
    static let completedActionsWingWidth: CGFloat = 136
    static let errorStatusWingWidth: CGFloat = 36
    static let minimumErrorMessageWingWidth: CGFloat = 132
    static let maximumErrorMessageWingWidth: CGFloat = 250

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
            return OverlayWingWidths(left: statusWingWidth, right: waveformWingWidth)
        case .preparingModel, .processingLocally, .inserting:
            return OverlayWingWidths(left: statusWingWidth, right: spinnerWingWidth)
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

struct AudioWaveformSmoother: Equatable {
    static let sampleCount = 7

    private(set) var level: Float = 0
    private(set) var samples = Array(repeating: Float.zero, count: sampleCount)

    mutating func update(rawLevel: Float) {
        let clamped = min(max(rawLevel.isFinite ? rawLevel : 0, 0), 1)
        let noiseGated = max((clamped - 0.025) / 0.975, 0)
        let sensitiveLevel = pow(noiseGated, 0.6)
        let response: Float = sensitiveLevel > level ? 0.72 : 0.28
        level += (sensitiveLevel - level) * response
        if level < 0.002 {
            level = 0
        }

        samples.removeFirst()
        samples.append(level)
    }

    mutating func reset() {
        level = 0
        samples = Array(repeating: 0, count: Self.sampleCount)
    }
}

@MainActor
final class OverlayModel: ObservableObject {
    @Published var state: OverlayState = .ready
    @Published var audioLevel: Float = 0
    @Published private(set) var waveformSamples = AudioWaveformSmoother().samples
    @Published var notchWidth: CGFloat = 0
    @Published var reservesHardwareNotch = false
    private var waveformSmoother = AudioWaveformSmoother()

    var onFix: @MainActor () -> Void = {}
    var onTeach: @MainActor () -> Void = {}

    var presentation: OverlayPresentation {
        OverlayPresentation(state: state)
    }

    func updateAudioLevel(_ level: Float) {
        waveformSmoother.update(rawLevel: level)
        audioLevel = waveformSmoother.level
        waveformSamples = waveformSmoother.samples
    }

    func resetAudioLevel() {
        waveformSmoother.reset()
        audioLevel = 0
        waveformSamples = waveformSmoother.samples
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

    var accent: OverlayAccent {
        if case .error = state { return .error }
        if state == .inserted || state == .copiedToClipboard { return .success }
        return state.isActive ? .active : .inactive
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
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(orange)
                .scaleEffect(0.78)
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
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(model.waveformSamples.enumerated()), id: \.offset) { _, sample in
                let clampedSample = min(max(sample, 0), 1)
                Capsule(style: .continuous)
                    .fill(orange.opacity(0.38 + Double(clampedSample) * 0.62))
                    .frame(
                        width: 2,
                        height: 3 + CGFloat(clampedSample) * 17
                    )
            }
        }
        .frame(width: 34, height: 22)
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
