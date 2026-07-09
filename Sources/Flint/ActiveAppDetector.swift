import AppKit
import Foundation

struct ActiveAppInfo: Equatable {
    let name: String?
    let bundleIdentifier: String?
}

struct ActiveAppDetector {
    private let provider: @MainActor () -> ActiveAppInfo

    init(provider: @escaping @MainActor () -> ActiveAppInfo = ActiveAppDetector.detectWithNSWorkspace) {
        self.provider = provider
    }

    @MainActor
    func detect() -> ActiveAppInfo {
        provider()
    }

    @MainActor
    private static func detectWithNSWorkspace() -> ActiveAppInfo {
        let app = NSWorkspace.shared.frontmostApplication
        return ActiveAppInfo(
            name: app?.localizedName,
            bundleIdentifier: app?.bundleIdentifier
        )
    }
}
