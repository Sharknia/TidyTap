import Foundation

/// Centralized UI strings keep Korean and English copy consistent.
enum TidyTapStrings {
    static let appName = String(localized: "TidyTap", bundle: .main)
    static let capsLockInputSourceSwitching = String(localized: "Use Caps Lock to switch input source", bundle: .main)
    static let reverseMouseWheelVertically = String(localized: "Reverse vertical mouse wheel direction", bundle: .main)
    static let sideButtonNavigation = String(localized: "Use side buttons for back/forward in Safari and Finder", bundle: .main)
    static let options = String(localized: "Options", bundle: .main)
    static let launchAtLogin = String(localized: "Start at login", bundle: .main)
    static let versionFormat = String(localized: "Version %@", bundle: .main)
    static let permissionRequired = String(localized: "Permission is required for this feature.", bundle: .main)
    static let accessibilityPermissionRequired = String(localized: "Accessibility permission is required for mouse features.", bundle: .main)
    static let inputMonitoringPermissionRequired = String(localized: "Input Monitoring permission is required for mouse wheel reversal.", bundle: .main)
    static let requestAccessibilityPermission = String(localized: "Request Accessibility Permission", bundle: .main)
    static let requestInputMonitoringPermission = String(localized: "Request Input Monitoring Permission", bundle: .main)
    static let applyingChanges = String(localized: "Applying changes…", bundle: .main)
    static let changesApplied = String(localized: "Changes applied.", bundle: .main)
    static let changesCouldNotBeApplied = String(localized: "Changes could not be applied.", bundle: .main)
    static let email = "zel@kakao.com"
    static let emailURL = URL(string: "mailto:zel@kakao.com")!
    static let github = "github.com/Sharknia/TidyTap"
    static let githubURL = URL(string: "https://github.com/Sharknia/TidyTap")!
}
