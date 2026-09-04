import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
    private var settingsCoordinator: SettingsCoordinator?
    private var observesApplyResults = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settingsCoordinator = SettingsCoordinator(helperLauncher: HelperLauncher())
        self.settingsCoordinator = settingsCoordinator
        settingsCoordinator.restoreSession()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(applyResultDidArrive(_:)),
            name: TidyTapIPC.applyResult,
            object: TidyTapProduct.appBundleIdentifier,
            suspensionBehavior: .deliverImmediately
        )
        observesApplyResults = true

        let controller = SettingsViewController()
        let window = NSWindow(contentViewController: controller)
        window.title = TidyTapStrings.appName
        window.setContentSize(NSSize(width: 520, height: 420))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()

        let windowController = NSWindowController(window: window)
        self.windowController = windowController
        windowController.showWindow(self)
    }

    deinit {
        if observesApplyResults {
            DistributedNotificationCenter.default().removeObserver(self)
        }
    }

    @objc private func applyResultDidArrive(_ notification: Notification) {
        _ = settingsCoordinator?.receiveApplyResult()
    }
}
