import Foundation

/// Names shared by the settings app and the background helper.
/// Posting and receiving are deliberately deferred until the helper lifecycle
/// is implemented.
enum TidyTapIPC {
    static let settingsDidChange = Notification.Name("com.sharknia.TidyTap.settingsDidChange")
    static let applyResult = Notification.Name("com.sharknia.TidyTap.applyResult")
}
