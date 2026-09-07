import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowController: NSWindowController?
    private var settingsCoordinator: SettingsCoordinator?
    private let launchSmoke = TidyTapLaunchSmoke.current()
    private let permissionSettingsOpener: TidyTapPermissionSettingsOpening
    private let initialFinderFeedback: TidyTapFinderFeedbackPayload?
    private var finderFeedbackPanel: FinderFeedbackPanelController?
    private var feedbackHostTermination: DispatchWorkItem?
    private var pendingPermissionSettingsOpen: TidyTapPendingPermissionSettingsOpen?

    init(
        permissionSettingsOpener: TidyTapPermissionSettingsOpening = SystemPermissionSettingsOpener(),
        initialFinderFeedback: TidyTapFinderFeedbackPayload? = nil
    ) {
        self.permissionSettingsOpener = permissionSettingsOpener
        self.initialFinderFeedback = initialFinderFeedback
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(finderFeedbackDidArrive(_:)),
            name: TidyTapIPC.finderFeedback,
            object: TidyTapProduct.appBundleIdentifier,
            suspensionBehavior: .deliverImmediately
        )
        TidyTapIPC.postFinderFeedbackReady()
        if let initialFinderFeedback {
            NSApp.setActivationPolicy(.accessory)
            showFinderFeedback(initialFinderFeedback, terminateAfterDisplay: true)
            if let rawNonce = ProcessInfo.processInfo.environment[
                TidyTapIPC.finderFeedbackNonceEnvironmentKey
            ], let nonce = UUID(uuidString: rawNonce) {
                TidyTapIPC.postFinderFeedbackReady(nonce: nonce)
            }
            return
        }
        startSettingsSession()
    }

    private func startSettingsSession() {
        guard settingsCoordinator == nil else {
            showSettingsWindow()
            return
        }
        feedbackHostTermination?.cancel()
        feedbackHostTermination = nil
        finderFeedbackPanel?.hide()
        // The settings app is a regular, user-facing application even though
        // its embedded helper is an agent. Explicitly restore the regular
        // activation policy so launches from a login item/Dock are visible.
        NSApp.setActivationPolicy(.regular)
        let menuBar = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: TidyTapStrings.appName)
        appMenu.addItem(withTitle: TidyTapStrings.quitApp,
                        action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menuBar.addItem(appItem)
        NSApp.mainMenu = menuBar
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
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(permissionResultDidArrive(_:)),
            name: TidyTapIPC.permissionResult,
            object: TidyTapProduct.appBundleIdentifier,
            suspensionBehavior: .deliverImmediately
        )
        settingsCoordinator.restoreSession()

        let controller = SettingsViewController(
            settings: settingsCoordinator.settingsForUI(),
            permissionState: settingsCoordinator.latestPermissionState ?? .init(),
            delegate: self
        )
        let window = NSWindow(contentViewController: controller)
        window.title = TidyTapStrings.appName
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.setContentSize(contentSizeThatFitsVisibleFrame(for: window))
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.isMovableByWindowBackground = true
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

    /// Keep the complete settings view visible on ordinary displays while
    /// leaving enough of the screen work area around a smaller display's
    /// window. The controller supplies vertical scrolling for the remainder.
    private func contentSizeThatFitsVisibleFrame(for window: NSWindow) -> NSSize {
        let desired = SettingsViewController.contentSize
        guard let screen = NSScreen.main ?? NSScreen.screens.first else {
            return desired
        }

        let desiredContentRect = NSRect(origin: .zero, size: desired)
        let desiredFrame = window.frameRect(forContentRect: desiredContentRect)
        let chromeHeight = desiredFrame.height - desired.height
        let maximumContentHeight = max(1, screen.visibleFrame.height - chromeHeight - 24)
        return NSSize(width: desired.width, height: min(desired.height, maximumContentHeight))
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        _ = updatePermissionResultIfAvailable()
        _ = try? settingsCoordinator?.refreshPermissionsIfNeeded()
    }

    /// Reopen the settings surface when the Dock icon or a status-item menu
    /// asks the already-running application to open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        startSettingsSession()
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
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func applyResultDidArrive(_ notification: Notification) {
        guard let coordinator = settingsCoordinator,
              let status = coordinator.receiveApplyResult(),
              let controller = windowController?.contentViewController as? SettingsViewController else {
            return
        }
        controller.apply(coordinator.visibleSettings(for: status))
        if let permissionState = coordinator.latestPermissionState {
            controller.applyPermissionState(permissionState)
        }
        controller.showApplyStatus(
            status,
            permission: coordinator.permissionSettingsPane(for: status)
        )
    }

    @objc private func permissionResultDidArrive(_ notification: Notification) {
        _ = updatePermissionResultIfAvailable()
    }

    @objc private func finderFeedbackDidArrive(_ notification: Notification) {
        guard let payload = TidyTapIPC.finderFeedback(in: notification) else { return }
        showFinderFeedback(payload, terminateAfterDisplay: settingsCoordinator == nil)
    }

    private func showFinderFeedback(
        _ payload: TidyTapFinderFeedbackPayload,
        terminateAfterDisplay: Bool
    ) {
        let isFinderFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        let isCurrentClipboard = NSPasteboard.general.changeCount == payload.clipboardChangeCount
        guard isFinderFrontmost, isCurrentClipboard else {
            launchSmoke?.report("feedback-suppressed-finder-\(isFinderFrontmost)-clipboard-\(isCurrentClipboard)")
            if terminateAfterDisplay {
                NSApp.terminate(nil)
            }
            return
        }
        let panel = finderFeedbackPanel ?? FinderFeedbackPanelController()
        finderFeedbackPanel = panel
        let message = switch payload.kind {
        case .moveReady: TidyTapStrings.finderMoveReady
        case .copyReady: TidyTapStrings.finderCopyReady
        }
        panel.show(message: message, anchorRect: payload.anchorRect)
        launchSmoke?.report("feedback-panel-shown")
        guard terminateAfterDisplay else { return }
        feedbackHostTermination?.cancel()
        let termination = DispatchWorkItem { NSApp.terminate(nil) }
        feedbackHostTermination = termination
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.05, execute: termination)
    }

    @discardableResult
    private func updatePermissionResultIfAvailable() -> Bool {
        guard let coordinator = settingsCoordinator,
              let controller = windowController?.contentViewController as? SettingsViewController,
              let result = coordinator.receivePermissionResult() else {
            return false
        }
        controller.applyPermissionState(result.state)
        if let status = coordinator.latestApplyStatus,
           status.failedComponent == .eventTap {
            controller.showApplyStatus(
                status,
                permission: coordinator.permissionSettingsPane(for: status, confirmed: result.state)
            )
        }
        if let requestedPane = pendingPermissionSettingsOpen?.consume(matching: result) {
            permissionSettingsOpener.open(requestedPane)
        }
        return true
    }
}

private final class LaunchSmokeHelperLauncher: TidyTapHelperLaunching {
    private let smoke: TidyTapLaunchSmoke

    init(smoke: TidyTapLaunchSmoke) {
        self.smoke = smoke
    }

    func ensureHelperRunning() {
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
        guard permission == .accessibility else { return true }
        guard let coordinator = settingsCoordinator else { return false }
        do {
            let requestID = try coordinator.requestPermission(permission)
            // The helper makes the native request first. System Settings opens
            // only after its matching response, never for a refresh result.
            pendingPermissionSettingsOpen = TidyTapPendingPermissionSettingsOpen(
                requestID: requestID,
                permission: permission
            )
            return true
        } catch {
            controller.showPermissionMessage(TidyTapStrings.changesCouldNotBeApplied, permission: permission)
            return true
        }
    }
}

@MainActor
protocol TidyTapPermissionSettingsOpening: AnyObject {
    func open(_ permission: TidyTapPermission)
}

/// Opens the exact Privacy & Security pane after the helper has asked macOS
/// for access. Keeping this behind a protocol makes smoke/tests non-mutating.
@MainActor
final class SystemPermissionSettingsOpener: TidyTapPermissionSettingsOpening {
    func open(_ permission: TidyTapPermission) {
        let url = SettingsCoordinator.permissionSettingsURL(for: permission)
        DispatchQueue.main.async {
            NSWorkspace.shared.open(url)
        }
    }
}
