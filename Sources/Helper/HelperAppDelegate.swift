import AppKit

/// A background-only helper. Its LSUIElement declaration lives in the helper
/// target build settings; feature controllers are intentionally not started yet.
@main
final class HelperAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Stage 1 scaffold: later stages apply the saved settings here.
    }
}
