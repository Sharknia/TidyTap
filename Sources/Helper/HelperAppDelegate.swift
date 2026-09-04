import AppKit
import TidyTapInputEngine

/// A background-only helper. It owns the process lifetime and applies the
/// complete persisted snapshot at launch and after each change notification.
@main
final class HelperAppDelegate: NSObject, NSApplicationDelegate {
    private var lifecycle: HelperLifecycle?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let preferences = TidyTapPreferencesStore()
        let coordinator = ApplyCoordinator(
            preferences: preferences,
            capsFeature: CapsLockFeatureAdapter(system: MacOSSystemApplyAdapter(), ownershipStore: preferences),
            inputFeatures: InputFeaturesAdapter(),
            menuBar: MenuBarController(),
            terminator: ApplicationTerminator()
        )
        let lifecycle = HelperLifecycle(coordinator: coordinator)
        self.lifecycle = lifecycle
        lifecycle.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        lifecycle?.stop()
    }
}
