import Foundation

/// The complete user-configurable state for the 0.1.0 settings domain.
///
/// Persistence and application of this value intentionally belong to later
/// stages; this shared model only establishes the contract used by both apps.
struct TidyTapSettings: Codable, Equatable {
    var capsLockInputSourceSwitching: Bool
    var reverseMouseWheelVertically: Bool
    var sideButtonNavigation: Bool
    var launchAtLogin: Bool
    var showInMenuBar: Bool

    static let defaults = TidyTapSettings(
        capsLockInputSourceSwitching: false,
        reverseMouseWheelVertically: false,
        sideButtonNavigation: false,
        launchAtLogin: false,
        showInMenuBar: false
    )
}

enum TidyTapPreferences {
    static let domain = "com.sharknia.TidyTap"
    static let settingsKey = "settings"
    static let applyRequestIDKey = "applyRequestID"
}
