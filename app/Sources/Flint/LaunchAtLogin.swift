import Foundation
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case disabled
    case enabled
    case requiresApproval
    case unavailable

    var isSelected: Bool {
        self == .enabled || self == .requiresApproval
    }
}

struct LaunchAtLoginController {
    enum LaunchAtLoginError: LocalizedError {
        case installedAppRequired

        var errorDescription: String? {
            switch self {
            case .installedAppRequired:
                return "Launch at Login is available after Flint.app is installed in Applications."
            }
        }
    }

    private let statusProvider: () -> LaunchAtLoginStatus
    private let updateHandler: (Bool) throws -> LaunchAtLoginStatus
    private let openSettingsHandler: () -> Void

    init(
        statusProvider: @escaping () -> LaunchAtLoginStatus,
        updateHandler: @escaping (Bool) throws -> LaunchAtLoginStatus,
        openSettingsHandler: @escaping () -> Void = {}
    ) {
        self.statusProvider = statusProvider
        self.updateHandler = updateHandler
        self.openSettingsHandler = openSettingsHandler
    }

    var status: LaunchAtLoginStatus {
        statusProvider()
    }

    @discardableResult
    func setEnabled(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        try updateHandler(enabled)
    }

    func openSystemSettings() {
        openSettingsHandler()
    }

    static let live = LaunchAtLoginController(
        statusProvider: currentStatus,
        updateHandler: update,
        openSettingsHandler: {
            SMAppService.openSystemSettingsLoginItems()
        }
    )

    private static func currentStatus() -> LaunchAtLoginStatus {
        guard isRunningFromAppBundle else { return .unavailable }
        return mappedStatus(SMAppService.mainApp.status)
    }

    private static func update(_ enabled: Bool) throws -> LaunchAtLoginStatus {
        guard isRunningFromAppBundle else {
            if enabled {
                throw LaunchAtLoginError.installedAppRequired
            }
            return .unavailable
        }

        let service = SMAppService.mainApp
        if enabled {
            switch service.status {
            case .enabled, .requiresApproval:
                break
            case .notRegistered, .notFound:
                try service.register()
            @unknown default:
                try service.register()
            }
        } else {
            switch service.status {
            case .enabled, .requiresApproval:
                try service.unregister()
            case .notRegistered, .notFound:
                break
            @unknown default:
                try service.unregister()
            }
        }
        return mappedStatus(service.status)
    }

    private static func mappedStatus(_ status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .notRegistered:
            return .disabled
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .unavailable
        @unknown default:
            return .unavailable
        }
    }

    private static var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.caseInsensitiveCompare("app") == .orderedSame
    }
}
