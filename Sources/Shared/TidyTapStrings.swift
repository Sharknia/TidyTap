import Foundation

/// Centralized keys keep the initial catalog limited to text frozen in the MVP
/// plan. UI wiring is intentionally deferred to a later stage.
enum TidyTapStrings {
    static let appName = String(localized: "TidyTap", bundle: .main)
    static let capsLockInputSourceSwitching = String(localized: "Use Caps Lock to switch input source", bundle: .main)
    static let reverseMouseWheelVertically = String(localized: "Reverse vertical mouse wheel direction", bundle: .main)
    static let sideButtonNavigation = String(localized: "Use side buttons for back/forward in Safari and Finder", bundle: .main)
    static let options = String(localized: "Options", bundle: .main)
    static let launchAtLogin = String(localized: "Start at login", bundle: .main)
    static let showInMenuBar = String(localized: "Show in menu bar", bundle: .main)
    static let openApp = String(localized: "Open TidyTap", bundle: .main)
    static let versionFormat = String(localized: "Version %@", bundle: .main)
}
