import CoreText
import Foundation
import SwiftUI

enum FlintTypography {
    static let headingFamily = "Space Grotesk"
    static let bodyFamily = "Inter"
    static let monoFamily = "IBM Plex Mono"

    static let bundledFontNames = [
        "SpaceGrotesk-Variable",
        "Inter-Variable",
        "IBMPlexMono-Regular",
        "IBMPlexMono-Medium",
        "IBMPlexMono-SemiBold"
    ]
    static let bundledFontLicenseNames = [
        "SpaceGrotesk-OFL",
        "Inter-OFL",
        "IBMPlexMono-OFL"
    ]

    private static var didRegisterBundledFonts = false

    static func registerBundledFonts() {
        guard !didRegisterBundledFonts else { return }
        didRegisterBundledFonts = true

        for fontURL in bundledFontURLs() {
            CTFontManagerRegisterFontsForURL(fontURL as CFURL, .process, nil)
        }
    }

    static func bundledFontURLs(mainBundle: Bundle = .main) -> [URL] {
        bundledFontNames.compactMap { name in
            mainBundle.url(forResource: name, withExtension: "ttf", subdirectory: "Fonts")
                ?? Bundle.module.url(
                    forResource: name,
                    withExtension: "ttf",
                    subdirectory: "Resources/Fonts"
                )
        }
    }

    static func bundledFontLicenseURLs(mainBundle: Bundle = .main) -> [URL] {
        bundledFontLicenseNames.compactMap { name in
            mainBundle.url(forResource: name, withExtension: "txt", subdirectory: "FontLicenses")
                ?? Bundle.module.url(
                    forResource: name,
                    withExtension: "txt",
                    subdirectory: "Resources/FontLicenses"
                )
        }
    }

    static func heading(size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        let fontName = weight == .bold ? "SpaceGrotesk-Bold" : "SpaceGrotesk-Medium"
        return .custom(fontName, fixedSize: size)
    }

    static func body(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let fontName: String
        if weight == .semibold || weight == .bold {
            fontName = "Inter-SemiBold"
        } else if weight == .medium {
            fontName = "Inter-Medium"
        } else {
            fontName = "Inter-Regular"
        }
        return .custom(fontName, fixedSize: size)
    }

    static func mono(size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let fontName: String
        if weight == .semibold || weight == .bold {
            fontName = "IBMPlexMono-SemiBold"
        } else if weight == .medium {
            fontName = "IBMPlexMono-Medium"
        } else {
            fontName = "IBMPlexMono-Regular"
        }
        return .custom(fontName, fixedSize: size)
    }
}
