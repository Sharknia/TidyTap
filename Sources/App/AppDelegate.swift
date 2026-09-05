import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
    private var settingsCoordinator: SettingsCoordinator?
    private var observesApplyResults = false
    private let launchSmoke = TidyTapLaunchSmoke.current()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The settings app is a regular, user-facing application even though
        // its embedded helper is an agent. Explicitly restore the regular
        // activation policy so launches from a login item/Dock are visible.
        NSApp.setActivationPolicy(.regular)
        let settingsCoordinator: SettingsCoordinator
        if let launchSmoke {
            settingsCoordinator = SettingsCoordinator(
                preferences: TidyTapPreferencesStore(defaults: launchSmoke.makePreferences()),
                helperLauncher: LaunchSmokeHelperLauncher(smoke: launchSmoke),
                loginItemManager: LaunchSmokeLoginItemCoordinator(smoke: launchSmoke)
            )
        } else {
            settingsCoordinator = SettingsCoordinator(helperLauncher: HelperLauncher())
        }
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
        window.isReleasedWhenClosed = false
        window.center()

        let windowController = NSWindowController(window: window)
        self.windowController = windowController
        showSettingsWindow()
        launchSmoke?.report("main-delegate-started")
        if let status = settingsCoordinator.latestApplyStatus {
            controller.showApplyStatus(
                status,
                permission: settingsCoordinator.permissionSettingsPane(for: status)
            )
        }
    }

    /// Reopen the settings surface when the Dock icon or a status-item menu
    /// asks the already-running application to open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsWindow()
        return true
    }

    /// Closing the settings window hides it but must not terminate the app:
    /// the helper may continue running independently.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func showSettingsWindow() {
        guard let window = windowController?.window else { return }
        if !window.isVisible {
            window.center()
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(self)
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

private final class LaunchSmokeHelperLauncher: TidyTapHelperLaunching {
    private let smoke: TidyTapLaunchSmoke

    init(smoke: TidyTapLaunchSmoke) {
        self.smoke = smoke
    }

    func launchOrActivateHelper() {
        smoke.report("main-helper-launch-skipped")
    }
}

private final class LaunchSmokeLoginItemCoordinator: TidyTapLoginItemManaging {
    private let smoke: TidyTapLaunchSmoke

    init(smoke: TidyTapLaunchSmoke) {
        self.smoke = smoke
    }

    func setEnabled(_ enabled: Bool) throws {
        smoke.report("main-login-item-mutation-skipped")
    }

    func status() -> TidyTapLoginItemStatus {
        .disabled
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
