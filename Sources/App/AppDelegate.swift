import AppKit

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
    private var settingsCoordinator: SettingsCoordinator?
    private var observesApplyResults = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let settingsCoordinator = SettingsCoordinator(helperLauncher: HelperLauncher())
        self.settingsCoordinator = settingsCoordinator
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(applyResultDidArrive(_:)),
            name: TidyTapIPC.applyResult,
            object: TidyTapProduct.appBundleIdentifier,
            suspensionBehavior: .deliverImmediately
        )
        observesApplyResults = true
        settingsCoordinator.restoreSession()

        let controller = SettingsViewController(
            settings: settingsCoordinator.settingsForUI(),
            delegate: self
        )
        let window = NSWindow(contentViewController: controller)
        window.title = TidyTapStrings.appName
        window.setContentSize(NSSize(width: 520, height: 420))
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.center()

        let windowController = NSWindowController(window: window)
        self.windowController = windowController
        windowController.showWindow(self)
        if let status = settingsCoordinator.latestApplyStatus {
            controller.showApplyStatus(
                status,
                permission: settingsCoordinator.permissionSettingsPane(for: status)
            )
        }
    }

    deinit {
        if observesApplyResults {
            DistributedNotificationCenter.default().removeObserver(self)
        }
    }

    @objc private func applyResultDidArrive(_ notification: Notification) {
        guard let coordinator = settingsCoordinator,
              let status = coordinator.receiveApplyResult(),
              let controller = windowController?.contentViewController as? SettingsViewController else {
            return
        }
        controller.apply(coordinator.visibleSettings(for: status))
        controller.showApplyStatus(
            status,
            permission: coordinator.permissionSettingsPane(for: status)
        )
    }
}

extension AppDelegate: SettingsViewControllerDelegate {
    func settingsViewController(_ controller: SettingsViewController, didChange settings: TidyTapSettings) -> Bool {
        guard let coordinator = settingsCoordinator else { return false }
        do {
            let requestID = try coordinator.save(settings)
            if coordinator.loginItemStatus() != .enabled, settings.launchAtLogin {
                controller.apply(coordinator.settingsForUI())
                controller.showPermissionMessage(nil)
            }
            controller.showApplyStatus(.pending(requestID))
        } catch {
            controller.apply(coordinator.persistedSettings())
            controller.showPermissionMessage(TidyTapStrings.changesCouldNotBeApplied)
        }
        return true
    }

    func settingsViewControllerRequestsPermissionSettings(_ controller: SettingsViewController, permission: TidyTapPermission) -> Bool {
        let anchor = permission == .accessibility ? "Privacy_Accessibility" : "Privacy_ListenEvent"
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
        NSWorkspace.shared.open(url)
        return true
    }
}
