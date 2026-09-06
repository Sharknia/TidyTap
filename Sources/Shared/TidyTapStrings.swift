import Foundation

/// Centralized UI strings keep Korean and English copy consistent.
enum TidyTapStrings {
    static let appName = String(localized: "TidyTap", bundle: .main)
    static let quitApp = String(localized: "Quit TidyTap", bundle: .main)
    static let capsLockInputSourceSwitching = String(localized: "Use Caps Lock to switch input source", bundle: .main)
    static let reverseMouseWheelVertically = String(localized: "Reverse vertical mouse wheel direction", bundle: .main)
    static let fixedMouseWheelStepSize = String(localized: "Fixed wheel step size", bundle: .main)
    static let fixedMouseWheelStepSizeDescription = String(localized: "Scroll a consistent amount for each wheel click", bundle: .main)
    static let mouseWheelStepSize = String(localized: "Step size", bundle: .main)
    static func mouseWheelStepLines(_ lines: Int) -> String {
        String(format: String(localized: "%d lines", bundle: .main), lines)
    }
    static let sideButtonNavigation = String(localized: "Use side buttons for back/forward in Safari and Finder", bundle: .main)
    static let options = String(localized: "Options", bundle: .main)
    static let launchAtLogin = String(localized: "Start at login", bundle: .main)
    static let versionFormat = String(localized: "Version %@", bundle: .main)
    static let permissionRequired = String(localized: "Permission is required for this feature.", bundle: .main)
    static let accessibilityPermissionRequired = String(localized: "Accessibility is required. In System Settings > Privacy & Security > Accessibility, enable TidyTap. Return here; TidyTap will refresh to confirm access. Then turn your desired feature back on.", bundle: .main)
    static let inputMonitoringPermissionRequired = String(localized: "Input Monitoring is required. In System Settings > Privacy & Security > Input Monitoring, enable TidyTap. Return here; TidyTap will refresh to confirm access. Then turn your desired feature back on.", bundle: .main)
    static let openAccessibilitySettings = String(localized: "Open Accessibility Settings", bundle: .main)
    static let openInputMonitoringSettings = String(localized: "Open Input Monitoring Settings", bundle: .main)
    static let applyingChanges = String(localized: "Applying changes…", bundle: .main)
    static let changesApplied = String(localized: "Changes applied.", bundle: .main)
    static let changesCouldNotBeApplied = String(localized: "Changes could not be applied.", bundle: .main)
    static let email = "zel@kakao.com"
    static let emailURL = URL(string: "mailto:zel@kakao.com")!
    static let github = "github.com/Sharknia/TidyTap"
    static let githubURL = URL(string: "https://github.com/Sharknia/TidyTap")!
}
