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

    var hint: String {
        switch self {
        case .ready:
            return "Hold Right Option to dictate"
        case .listening:
            return "Release to insert · Esc cancel"
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
}

@MainActor
final class OverlayWindow {
    private let model = OverlayModel()
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
        positionWindow()
        window.orderFrontRegardless()

        if state == .ready || state == .cancelled || state == .copiedToClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak window] in
                window?.orderOut(nil)
            }
        }
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
                Text(model.state.label)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.primary)
                Spacer()
                Text("CLEAN")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.secondary)
            }

            levelMeter

            Text(model.state.hint)
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
        if case .error = model.state {
            return red
        }
        return model.state.isActive ? orange : Color.secondary
    }

    private var levelMeter: some View {
        HStack(spacing: 3) {
            ForEach(0..<18, id: \.self) { index in
                Rectangle()
                    .fill(index < filledBars ? orange : Color(nsColor: .separatorColor))
                    .frame(width: 10, height: 9)
            }
        }
        .frame(height: 10)
    }

    private var filledBars: Int {
        switch model.state {
        case .listening:
            return 9
        case .processingLocally, .inserting:
            return 14
        case .error:
            return 3
        default:
            return 0
        }
    }
}
