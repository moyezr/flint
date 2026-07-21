import SwiftUI

enum FlintBrand {
    static let signalHex: UInt32 = 0xFF4F1F
    static let paperHex: UInt32 = 0xF8F7F3
    static let mistHex: UInt32 = 0xE9E8E1
    static let inkHex: UInt32 = 0x121412
    static let deepHex: UInt32 = 0x151914
    static let mutedHex: UInt32 = 0x62675E
    static let lineHex: UInt32 = 0xC9CDC2

    static let signal = Color(hex: signalHex)
    static let paper = Color(hex: paperHex)
    static let mist = Color(hex: mistHex)
    static let ink = Color(hex: inkHex)
    static let deep = Color(hex: deepHex)
    static let muted = Color(hex: mutedHex)
    static let line = Color(hex: lineHex)
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
