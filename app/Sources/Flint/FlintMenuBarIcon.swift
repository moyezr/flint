import AppKit

enum FlintMenuBarIcon {
    static let size = NSSize(width: 18, height: 18)

    static func make(hasUpdate: Bool = false) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            NSColor.black.setFill()

            NSBezierPath(rect: NSRect(x: 1, y: 2, width: 2.1, height: 14)).fill()
            NSBezierPath(rect: NSRect(x: 1, y: 13.9, width: 8.1, height: 2.1)).fill()
            NSBezierPath(rect: NSRect(x: 1, y: 8.1, width: 7.7, height: 2.1)).fill()

            let slash = NSBezierPath()
            slash.move(to: NSPoint(x: 9.1, y: 2))
            slash.line(to: NSPoint(x: 10.8, y: 2))
            slash.line(to: NSPoint(x: 16.8, y: 16))
            slash.line(to: NSPoint(x: 15.1, y: 16))
            slash.close()
            slash.fill()

            if hasUpdate {
                NSBezierPath(ovalIn: NSRect(x: 14.6, y: 1.2, width: 2.8, height: 2.8)).fill()
            }

            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = hasUpdate ? "Flint, update available" : "Flint"
        return image
    }
}
