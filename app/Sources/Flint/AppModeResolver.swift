import Foundation

struct AppModeResolutionContext: Equatable {
    let appAwareModesEnabled: Bool
    let manualMode: CleanupMode
    let activeAppBundleID: String?

    init(
        appAwareModesEnabled: Bool,
        manualMode: CleanupMode,
        activeAppBundleID: String?
    ) {
        self.appAwareModesEnabled = appAwareModesEnabled
        self.manualMode = manualMode
        self.activeAppBundleID = activeAppBundleID
    }
}
struct AppModeResolver {
    func resolve(context: AppModeResolutionContext, rules: [AppModeRule]) -> CleanupMode {
        guard context.appAwareModesEnabled,
              let activeAppBundleID = context.activeAppBundleID?.trimmingCharacters(in: .whitespacesAndNewlines),
              !activeAppBundleID.isEmpty else {
            return context.manualMode
        }

        return rules
            .filter { rule in
                guard rule.enabled else { return false }
                return rule.appBundleID == activeAppBundleID
            }
            .sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt {
                    return lhs.id < rhs.id
                }
                return lhs.createdAt < rhs.createdAt
            }
            .first?
            .mode ?? context.manualMode
    }
}
