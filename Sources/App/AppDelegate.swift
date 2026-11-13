import AppKit
import CoreData
import CloudKit
import Sparkle
import TidyTapInputEngine

private struct ClipboardPasteTarget {
    let application: NSRunningApplication
    let sessionID: UUID
}

private struct ClipboardPasteDiagnostic {
    let sessionID: UUID
    let targetPID: pid_t
    let entry: ClipboardHistoryEntry
    let query: String
    let sourceIndex: Int
    let sourceCount: Int
    let resultCount: Int
    let startedAt = TidyTapContinuousClock.now()
    var activationAccepted: Bool?
    var dispatched = false
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, SPUUpdaterDelegate {
    private var clipboardLibraryPrepared = true
    private var clipboardSyncCoordinator: ClipboardSyncCoordinator?
    private var clipboardStoreObserver: NSObjectProtocol?
    private var clipboardAccountObserver: NSObjectProtocol?
    private var windowController: NSWindowController?
    private var settingsCoordinator: SettingsCoordinator?
    private let launchSmoke = TidyTapLaunchSmoke.current()
    private let permissionSettingsOpener: TidyTapPermissionSettingsOpening
    private let initialFinderFeedback: TidyTapFinderFeedbackPayload?
    private var finderFeedbackPanel: FinderFeedbackPanelController?
    private var feedbackHostTermination: DispatchWorkItem?
    private var pendingPermissionSettingsOpen: TidyTapPendingPermissionSettingsOpen?
    private var clipboardLibraryHandle: ClipboardLibraryHandle?
    private var clipboardHistoryPanel: ClipboardHistoryPanelController?
    private var clipboardPasteTarget: ClipboardPasteTarget?
    private var pendingClipboardPasteSessionID: UUID?
    private var pendingClipboardPasteEntryID: UUID?
    private var pendingClipboardPasteDiagnostic: ClipboardPasteDiagnostic?
    private var clipboardPasteFeedback: ClipboardPasteFeedbackPanelController?
    private var clipboardPasteScreen: NSScreen?
    private var lastClipboardPasteIssue: String?
    private var updaterController: SPUStandardUpdaterController?

    init(
        permissionSettingsOpener: TidyTapPermissionSettingsOpening = SystemPermissionSettingsOpener(),
        initialFinderFeedback: TidyTapFinderFeedbackPayload? = nil
    ) {
        self.permissionSettingsOpener = permissionSettingsOpener
        self.initialFinderFeedback = initialFinderFeedback
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let suite = launchSmoke?.preferencesSuite ?? TidyTapProduct.appBundleIdentifier
        do {
            try TidyTapProduct.prepareClipboardLegacyMigration(directory: TidyTapProduct.clipboardHistoryDirectory(preferencesSuite: suite)) {
                if let smoke = self.launchSmoke { LaunchSmokeHelperLauncher(smoke: smoke).ensureHelperRunning() }
                else { try HelperLauncher().ensureHelperRunning() }
            }
        } catch { clipboardLibraryPrepared = false }
        if clipboardLibraryPrepared { configureClipboardSync() }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(clipboardTargetDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        if launchSmoke == nil {
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(otherTidyTapDidLaunch(_:)),
                name: NSWorkspace.didLaunchApplicationNotification,
                object: nil
            )
        }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(clipboardHistoryToggle(_:)),
            name: TidyTapIPC.clipboardHistoryToggle,
            object: TidyTapIPC.clipboardNotificationObject,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(clipboardHistoryChanged(_:)),
            name: TidyTapIPC.clipboardHistoryChanged,
            object: TidyTapIPC.clipboardNotificationObject,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(clipboardHistoryPasteResult(_:)),
            name: TidyTapIPC.clipboardHistoryPasteResult,
            object: TidyTapIPC.clipboardNotificationObject,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(applyResultDidArrive(_:)),
            name: TidyTapIPC.applyResult,
            object: TidyTapIPC.notificationObject,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(finderFeedbackDidArrive(_:)),
            name: TidyTapIPC.finderFeedback,
            object: TidyTapIPC.notificationObject,
            suspensionBehavior: .deliverImmediately
        )
        if ProcessInfo.processInfo.environment[TidyTapIPC.clipboardHistoryModeEnvironmentKey] == "1" {
            toggleClipboardHistory(
                targetPID: TidyTapIPC.clipboardTargetPID(in: ProcessInfo.processInfo.environment),
                sessionID: TidyTapIPC.clipboardSessionID(in: ProcessInfo.processInfo.environment),
                displayID: TidyTapIPC.clipboardDisplayID(in: ProcessInfo.processInfo.environment)
            )
            TidyTapIPC.postFinderFeedbackReady()
            return
        }
        if ProcessInfo.processInfo.environment[TidyTapProduct.backgroundUpdateEnvironmentKey] == "1" {
            NSApp.setActivationPolicy(.accessory)
            try? HelperLauncher().ensureHelperRunning()
            TidyTapIPC.postFinderFeedbackReady()
            return
        }
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

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = clipboardStoreObserver { NotificationCenter.default.removeObserver(observer) }
        if let observer = clipboardAccountObserver { NotificationCenter.default.removeObserver(observer) }
        clipboardSyncCoordinator?.onStateChange = nil
        clipboardSyncCoordinator?.onLibraryChange = nil
    }

    private func configureClipboardSync() {
        let suite = launchSmoke?.preferencesSuite ?? TidyTapProduct.appBundleIdentifier
        let preferences = TidyTapPreferencesStore(defaults: launchSmoke?.makePreferences())
        do {
            let router = try TidyTapProduct.clipboardRouter(directory: TidyTapProduct.clipboardHistoryDirectory(preferencesSuite: suite))
            let identifier = Bundle.main.object(forInfoDictionaryKey: "TidyTapCloudKitContainerIdentifier") as? String ?? ""
            let testing = launchSmoke != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
                || NSClassFromString("XCTestCase") != nil
            let coordinator = ClipboardSyncCoordinator(router: router,
                account: CloudKitClipboardAccountProvider(containerIdentifier: identifier), transport: ClipboardLibraryMirror(),
                containerIdentifier: identifier, preflight: {
                    try ClipboardSyncCoordinator.validateLiveConfiguration(containerIdentifier: identifier, isTesting: testing)
                })
            clipboardSyncCoordinator = coordinator
            coordinator.onStateChange = { [weak self] state in
                if state == .syncing && !testing { NSApp.registerForRemoteNotifications() }
                guard let self, let controller = self.windowController?.contentViewController as? SettingsViewController else { return }
                controller.applyClipboardSync(enabled: preferences.readClipboardICloudSyncEnabled(), state: state,
                    pauseNeedsRetry: self.clipboardSyncCoordinator?.pauseNeedsRetry ?? false)
            }
            coordinator.onAccountWillChange = { [weak self] in
                self?.clipboardHistoryPanel?.close(restorePreviousApp: false)
                self?.clipboardLibraryHandle = nil; self?.clipboardPasteTarget = nil
                self?.pendingClipboardPasteSessionID = nil; self?.pendingClipboardPasteEntryID = nil
            }
            coordinator.onLibraryChange = { [weak self] in
                self?.clipboardHistoryChanged(Notification(name: TidyTapIPC.clipboardHistoryChanged))
            }
            clipboardStoreObserver = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange,
                object: nil, queue: nil) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.clipboardHistoryChanged(Notification(name: TidyTapIPC.clipboardHistoryChanged))
                    }
                }
            clipboardAccountObserver = NotificationCenter.default.addObserver(forName: .CKAccountChanged,
                object: nil, queue: nil) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let prefs = TidyTapPreferencesStore(defaults: self.launchSmoke?.makePreferences())
                        self.clipboardSyncCoordinator?.apply(enabled: prefs.readClipboardICloudSyncEnabled())
                    }
                }
            if preferences.readClipboardICloudSyncEnabled() { coordinator.apply(enabled: true) }
        } catch { }
    }

    private func startSettingsSession() {
        // A clipboard-only launch can later become a settings session when
        // LaunchServices reopens this same process. Start Sparkle at that point.
        if launchSmoke == nil && updaterController == nil {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil
            )
        }
        pruneClipboardHistoryIfPresent()
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
            selector: #selector(permissionResultDidArrive(_:)),
            name: TidyTapIPC.permissionResult,
            object: TidyTapIPC.notificationObject,
            suspensionBehavior: .deliverImmediately
        )
        settingsCoordinator.restoreSession()

        let controller = SettingsViewController(
            settings: settingsCoordinator.settingsForUI(),
            permissionState: settingsCoordinator.latestPermissionState ?? .init(),
            delegate: self
        )
        controller.applyClipboardSync(enabled: settingsCoordinator.readClipboardICloudSyncEnabled(),
            state: clipboardSyncCoordinator?.state ?? .failed, pauseNeedsRetry: clipboardSyncCoordinator?.pauseNeedsRetry ?? false)
        controller.onRetryClipboardSync = { [weak self] in
            guard let self, let settings = self.settingsCoordinator else { return }
            self.clipboardSyncCoordinator?.apply(enabled: settings.readClipboardICloudSyncEnabled())
        }
        controller.onClearClipboardHistory = { [weak self, weak controller] in
            self?.clearClipboardHistory(settingsController: controller)
        }
        if let updaterController {
            controller.onCheckForUpdates = { updaterController.checkForUpdates(nil) }
        }
        let window = NSWindow(contentViewController: controller)
        window.title = TidyTapStrings.appName
        window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        window.setContentSize(contentSizeThatFitsVisibleFrame(for: window))
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.center()

        let windowController = NSWindowController(window: window)
        self.windowController = windowController
        showSettingsWindow()
        launchSmoke?.report(
            "settings-window-frame-\(Int(window.frame.width))x\(Int(window.frame.height))-" +
                "content-\(Int(window.contentLayoutRect.width))x\(Int(window.contentLayoutRect.height))"
        )
        launchSmoke?.report("main-delegate-started")
        if let status = settingsCoordinator.latestApplyStatus {
            controller.showApplyStatus(
                status,
                permission: settingsCoordinator.permissionSettingsPane(for: status)
            )
        }
    }

    /// History can be disabled while the helper is not running. Reopening
    /// settings is another chance to remove entries that expired meanwhile.
    private func pruneClipboardHistoryIfPresent() {
        guard clipboardLibraryPrepared else { return }
        let suite = launchSmoke?.preferencesSuite ?? TidyTapProduct.appBundleIdentifier
        let directory = TidyTapProduct.clipboardHistoryDirectory(preferencesSuite: suite)
        guard FileManager.default.fileExists(atPath: directory.path)
            || FileManager.default.fileExists(atPath: directory.deletingLastPathComponent().appendingPathComponent("clipboard-library-v2").path) else { return }
        guard let store = try? TidyTapProduct.clipboardLibrary(
            directory: directory,
            retention: TidyTapClipboardPolicy.retention,
            maximumEntries: TidyTapClipboardPolicy.maximumEntries,
            maximumBytes: TidyTapClipboardPolicy.maximumBytes,
            maximumItemBytes: TidyTapClipboardPolicy.maximumItemBytes
        ) else { return }
        if let entries = try? store.entries() {
            launchSmoke?.report("clipboard-library-history-count-\(entries.count)")
            let valid = entries.allSatisfy { Date().timeIntervalSince($0.copiedAt) < TidyTapClipboardPolicy.retention }
            launchSmoke?.report("clipboard-library-expiry-valid-\(valid)")
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
        if clipboardHistoryPanel?.isVisible == true { return true }
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
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func otherTidyTapDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == TidyTapProduct.appBundleIdentifier,
              app.processIdentifier != getpid(),
              TidyTapProduct.isSameSignedApp(app) else { return }
        // A same-version second process exits on app.lock. Wait for that exit
        // before treating a still-running copy as an older installation.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if !app.isTerminated { NSApp.terminate(nil) }
        }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        TidyTapIPC.postPrepareForUpdate()
        let runtime = SystemTidyTapWorkerRuntime()
        for _ in 0..<40 {
            if case .free = try? runtime.inspectLock() { return }
            usleep(50_000)
        }
    }

    @objc private func clipboardHistoryToggle(_ notification: Notification) {
        launchSmoke?.report("clipboard-toggle-received target=\(TidyTapIPC.clipboardTargetPID(in: notification) ?? 0) frontmost=\(NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)")
        toggleClipboardHistory(
            targetPID: TidyTapIPC.clipboardTargetPID(in: notification),
            sessionID: TidyTapIPC.clipboardSessionID(in: notification),
            displayID: TidyTapIPC.clipboardDisplayID(in: notification)
        )
    }

    @objc private func clipboardHistoryPasteResult(_ notification: Notification) {
        guard let result = TidyTapIPC.clipboardPasteResult(in: notification),
              result.sessionID == pendingClipboardPasteSessionID else { return }
        TidyTapClipboardPasteLog.record(
            "appResult session=\(result.sessionID.uuidString.prefix(8)) " +
            "reason=\(result.error ?? "pasteEventPosted")"
        )
        recordPasteStage("result reason=\(result.error ?? "pasteEventPosted")")
        logPendingClipboardSelection(outcome: result.error ?? "pasteEventPosted")
        pendingClipboardPasteSessionID = nil
        pendingClipboardPasteEntryID = nil
        clipboardProbeReport("helper result=\(result.error ?? "posted")")
        if result.error == "superseded" {
            return
        } else if let error = result.error {
            showClipboardError(reason: error)
        } else {
            lastClipboardPasteIssue = nil
            clipboardHistoryPanel?.setPreviousAttempt(nil)
        }
    }

    @objc private func clipboardHistoryChanged(_ notification: Notification) {
        guard let panel = clipboardHistoryPanel, panel.isVisible, let store = clipboardLibraryHandle else { return }
        do {
            guard try store.router.currentRoute() == store.route else {
                panel.close(restorePreviousApp: false); clipboardLibraryHandle = nil; return
            }
            let latestCopyTooLarge = store.oversizedCopyChangeCount().map { $0 == NSPasteboard.general.changeCount } ?? false
            panel.refreshPreservingSelection(try store.snapshot(), latestCopyTooLarge: latestCopyTooLarge)
        } catch { }
    }

    private func toggleClipboardHistory(targetPID: pid_t?, sessionID: UUID?, displayID: UInt32?) {
        clipboardPasteFeedback?.hide()
        if let pending = pendingClipboardPasteSessionID, pending != sessionID {
            logPendingClipboardSelection(outcome: "superseded")
            pendingClipboardPasteSessionID = nil
            pendingClipboardPasteEntryID = nil
        }
        if clipboardHistoryPanel?.isVisible == true {
            clipboardHistoryPanel?.close()
            return
        }
        let frontmost = NSWorkspace.shared.frontmostApplication
        let targetApplication = targetPID.flatMap(NSRunningApplication.init(processIdentifier:))
        launchSmoke?.report("clipboard-open-state sessionValid=\(sessionID != nil) frontmost=\(frontmost?.processIdentifier ?? 0) target=\(targetPID ?? 0) appExists=\(targetApplication != nil)")
        guard let targetPID, let sessionID, targetPID != getpid(),
              frontmost?.processIdentifier == targetPID,
              let application = targetApplication else { return }
        clipboardProbeReport("opened")

        do {
            guard clipboardLibraryPrepared else { throw ClipboardLibraryStore.StoreError.invalidStore }
            let suite = launchSmoke?.preferencesSuite ?? TidyTapProduct.appBundleIdentifier
            let store = try TidyTapProduct.clipboardLibrary(
                directory: TidyTapProduct.clipboardHistoryDirectory(preferencesSuite: suite),
                retention: TidyTapClipboardPolicy.retention,
                maximumEntries: TidyTapClipboardPolicy.maximumEntries,
                maximumBytes: TidyTapClipboardPolicy.maximumBytes,
                maximumItemBytes: TidyTapClipboardPolicy.maximumItemBytes
            )
            let entries = try store.entries()
            let latestCopyTooLarge = store.oversizedCopyChangeCount()
                .map { $0 == NSPasteboard.general.changeCount } ?? false
            let preferences = TidyTapPreferencesStore(defaults: launchSmoke?.makePreferences())
            clipboardPasteTarget = ClipboardPasteTarget(application: application, sessionID: sessionID)
            let panel = clipboardHistoryPanel ?? ClipboardHistoryPanelController()
            clipboardHistoryPanel = panel
            // Activating the history panel also raises other windows owned by
            // this app. Keep Settings out of the way until explicitly reopened.
            windowController?.window?.orderOut(nil)
            panel.setPreviousAttempt(lastClipboardPasteIssue.map { TidyTapStrings.clipboardPastePreviousAttempt(for: $0) })
            clipboardLibraryHandle = store
            let opened = panel.show(
                snapshot: try store.snapshot(),
                displayID: displayID,
                pasteFormattedByDefault: preferences.readRequest().settings.pasteFormattedTextByDefault,
                latestCopyTooLarge: latestCopyTooLarge,
                onPaste: { [weak self, weak panel] entry, style in
                    guard let self else { return }
                    let sessionID = self.clipboardPasteTarget?.sessionID ?? UUID()
                    self.clipboardPasteScreen = panel?.pasteScreen
                    let query = panel?.searchQuery ?? ""
                    let source = panel?.sourcePosition(for: entry.id)
                    self.pendingClipboardPasteDiagnostic = ClipboardPasteDiagnostic(
                        sessionID: sessionID, targetPID: targetPID,
                        entry: entry, query: query,
                        sourceIndex: source?.index ?? -1, sourceCount: source?.count ?? 0,
                        resultCount: panel?.visibleCount ?? 0
                    )
                    self.paste(entry, style: style)
                },
                onSetPinned: { id, desired, completion in
                    do { try store.setPinned(id, pinned: desired); completion(.success(try store.snapshot())) }
                    catch { completion(.failure(error)) }
                },
                onDeleteHistory: { [weak self] id, completion in
                    do {
                        guard TidyTapClipboardPasteLog.clear() else { throw ClipboardLibraryStore.StoreError.invalidPath }
                        if self?.pendingClipboardPasteDiagnostic?.entry.id == id {
                            self?.pendingClipboardPasteDiagnostic = nil
                        }
                        try store.delete(id); completion(.success(try store.snapshot()))
                    } catch { completion(.failure(error)) }
                },
                onCancel: { [weak self] restorePreviousApp in
                    guard let self else { return }
                    let target = self.clipboardPasteTarget
                    self.clipboardPasteTarget = nil
                    if restorePreviousApp, let target, !target.application.isTerminated {
                        _ = target.application.activate(options: [])
                    }
                }
            )
            if !opened { clipboardPasteTarget = nil; clipboardLibraryHandle = nil; showClipboardOpenError() }
            launchSmoke?.report("clipboard-panel-visible=\(panel.isVisible) entries=\(entries.count) window=\(panel.panel.windowNumber)")
        } catch {
            showClipboardOpenError()
        }
    }

    private func paste(_ entry: ClipboardHistoryEntry, style: ClipboardTextPasteStyle) {
        pendingClipboardPasteSessionID = nil
        pendingClipboardPasteEntryID = nil
        lastClipboardPasteIssue = nil
        clipboardHistoryPanel?.setPreviousAttempt(nil)
        recordPasteStage("attempt")
        promotePastedHistoryEntry(entry.id)
        guard let target = clipboardPasteTarget, !target.application.isTerminated else {
            showClipboardError(reason: "targetUnavailable")
            return
        }
        clipboardPasteTarget = nil
        pendingClipboardPasteSessionID = target.sessionID
        pendingClipboardPasteEntryID = entry.id
        clipboardProbeReport("paste requested")
        let deadlineContinuousTime = TidyTapContinuousClock.now() + 1.5
        let activated = target.application.activate(options: [])
        clipboardProbeReport("activation=\(activated)")
        pendingClipboardPasteDiagnostic?.activationAccepted = activated
        recordPasteStage("activation accepted=\(activated)")
        pasteWhenTargetIsActive(
            entry, style: style, target: target, attemptsRemaining: 15,
            deadlineContinuousTime: deadlineContinuousTime
        )
    }

    private func pasteWhenTargetIsActive(
        _ entry: ClipboardHistoryEntry,
        style: ClipboardTextPasteStyle,
        target: ClipboardPasteTarget,
        attemptsRemaining: Int,
        deadlineContinuousTime: TimeInterval
    ) {
        guard pendingClipboardPasteSessionID == target.sessionID else { return }
        guard TidyTapContinuousClock.now() < deadlineContinuousTime else {
            showClipboardError(reason: "focusDeadlineExceeded")
            return
        }
        guard !target.application.isTerminated else {
            showClipboardError(reason: "targetUnavailable")
            return
        }
        let processID = target.application.processIdentifier
        let frontmost = NSWorkspace.shared.frontmostApplication
        recordPasteStage("activationCheck target=\(processID) frontmost=\(frontmost?.processIdentifier ?? 0) app=\(frontmost?.bundleIdentifier ?? "none") terminated=\(target.application.isTerminated)")
        if frontmost?.processIdentifier != processID {
            guard attemptsRemaining > 0 else {
                clipboardProbeReport("target not frontmost")
                showClipboardError(reason: "targetUnavailable")
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) { [weak self] in
                self?.pasteWhenTargetIsActive(
                    entry, style: style, target: target,
                    attemptsRemaining: attemptsRemaining - 1,
                    deadlineContinuousTime: deadlineContinuousTime
                )
            }
            return
        }
        pendingClipboardPasteDiagnostic?.dispatched = true
        recordPasteStage("dispatch")
        guard let handle = clipboardLibraryHandle, (try? handle.router.currentRoute()) == handle.route else {
            showClipboardError(reason: "entryUnavailable"); return
        }
        TidyTapIPC.postClipboardHistoryPaste(
            sessionID: target.sessionID,
            entryID: entry.id,
            formatted: style == .formatted,
            deadlineContinuousTime: deadlineContinuousTime,
            route: handle.route
        )
        clipboardProbeReport("paste sent to helper")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            guard let self, self.pendingClipboardPasteSessionID == target.sessionID else { return }
            self.pendingClipboardPasteSessionID = nil
            self.pendingClipboardPasteEntryID = nil
            self.clipboardProbeReport("helper result=timeout")
            self.showClipboardError(reason: "helperTimeout")
        }
    }

    private func promotePastedHistoryEntry(_ id: UUID) {
        do {
            guard let store = clipboardLibraryHandle, try store.router.currentRoute() == store.route else { return }
            let promoted = try store.promote(id)
            recordPasteStage("promotion result=\(promoted == nil ? "missing" : "promoted")")
        } catch {
            recordPasteStage("promotion result=storageFailure")
        }
    }

    private func clipboardProbeReport(_ event: String) {
        guard launchSmoke != nil,
              ProcessInfo.processInfo.environment[TidyTapIPC.clipboardHistoryModeEnvironmentKey] == "1",
              let path = ProcessInfo.processInfo.environment["TIDYTAP_CLIPBOARD_G1_LOG_PATH"],
              let handle = try? FileHandle(forWritingTo: URL(fileURLWithPath: path)) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: Data("clipboard-g1: \(event)\n".utf8))
    }

    private func showClipboardError(reason: String? = nil) {
        recordPasteStage("result reason=\(reason ?? "unknown")")
        pendingClipboardPasteSessionID = nil
        pendingClipboardPasteEntryID = nil
        NSLog("TidyTap clipboard paste failed: %@", reason ?? "unknown")
        TidyTapClipboardPasteLog.record("appFailure reason=\(reason ?? "unknown")")
        logPendingClipboardSelection(outcome: reason ?? "unknown")
        let issue = reason ?? "unknown"
        lastClipboardPasteIssue = issue
        clipboardHistoryPanel?.setPreviousAttempt(TidyTapStrings.clipboardPastePreviousAttempt(for: issue))
        let feedback = clipboardPasteFeedback ?? ClipboardPasteFeedbackPanelController()
        clipboardPasteFeedback = feedback
        feedback.show(message: TidyTapStrings.clipboardPasteNotice(for: reason), on: clipboardPasteScreen)
    }

    private func recordPasteStage(_ phase: String) {
        guard let diagnostic = pendingClipboardPasteDiagnostic else { return }
        TidyTapClipboardPasteLog.record(
            "appStage session=\(diagnostic.sessionID.uuidString) elapsed=\(TidyTapContinuousClock.now() - diagnostic.startedAt) phase=\(phase)"
        )
    }

    @objc private func clipboardTargetDidActivate(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        recordPasteStage("didActivate app=\(app.bundleIdentifier ?? "none") frontmost=\(app.processIdentifier)")
    }

    private func logPendingClipboardSelection(outcome: String) {
        guard let diagnostic = pendingClipboardPasteDiagnostic else { return }
        pendingClipboardPasteDiagnostic = nil
        let session = diagnostic.sessionID.uuidString.prefix(8)
        TidyTapClipboardPasteLog.record(
            "selectionContext session=\(session) targetPID=\(diagnostic.targetPID) " +
            "sourceIndex=\(diagnostic.sourceIndex) sourceCount=\(diagnostic.sourceCount) " +
            "resultCount=\(diagnostic.resultCount) searchNonempty=\(!diagnostic.query.isEmpty) " +
            "activationAccepted=\(diagnostic.activationAccepted.map { String(describing: $0) } ?? "none") " +
            "dispatched=\(diagnostic.dispatched)"
        )
    }

    private func showClipboardOpenError() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Could not open clipboard history")
        alert.informativeText = String(localized: "Check available storage and try again.")
        presentClipboardAlert(alert)
    }

    private func showClipboardDeleteError() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Could not delete the selected item")
        alert.informativeText = String(localized: "Check available storage and try again.")
        presentClipboardAlert(alert)
    }

    private func presentClipboardAlert(_ alert: NSAlert) {
        alert.window.level = .statusBar
        alert.window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        NSApp.activate(ignoringOtherApps: true)
        alert.window.orderFrontRegardless()
        alert.runModal()
    }

    private func clearClipboardHistory(settingsController: SettingsViewController?) {
        do {
            guard clipboardLibraryPrepared else { throw ClipboardLibraryStore.StoreError.invalidStore }
            pendingClipboardPasteDiagnostic = nil
            pendingClipboardPasteSessionID = nil
            pendingClipboardPasteEntryID = nil
            guard TidyTapClipboardPasteLog.clear() else {
                settingsController?.showClipboardClearStatus(success: false)
                return
            }
            let store = try TidyTapProduct.clipboardLibrary(
                directory: TidyTapProduct.clipboardHistoryDirectory(
                    preferencesSuite: launchSmoke?.preferencesSuite ?? TidyTapProduct.appBundleIdentifier
                ),
                retention: TidyTapClipboardPolicy.retention,
                maximumEntries: TidyTapClipboardPolicy.maximumEntries,
                maximumBytes: TidyTapClipboardPolicy.maximumBytes,
                maximumItemBytes: TidyTapClipboardPolicy.maximumItemBytes
            )
            try store.deleteAll()
            clipboardHistoryPanel?.refreshPreservingSelection(try store.snapshot())
            settingsController?.showClipboardClearStatus(success: true)
        } catch {
            settingsController?.showClipboardClearStatus(success: false)
        }
    }

    @objc private func applyResultDidArrive(_ notification: Notification) {
        let preferences = TidyTapPreferencesStore(defaults: launchSmoke?.makePreferences())
        let request = preferences.readRequest()
        let applied = preferences.readApplyStatus()
        if request.settings.clipboardHistoryIsEffectivelyOff(
            requestID: request.applyRequestID, status: applied
        ) {
            clipboardHistoryPanel?.close(restorePreviousApp: settingsCoordinator == nil)
        }
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
        showFinderFeedback(
            payload,
            terminateAfterDisplay: settingsCoordinator == nil && clipboardHistoryPanel == nil
        )
    }

    private var keepsClipboardSyncOwnerAlive: Bool { clipboardSyncCoordinator?.needsOwnerLifetime == true }

    private func showFinderFeedback(
        _ payload: TidyTapFinderFeedbackPayload,
        terminateAfterDisplay: Bool
    ) {
        let isFinderFrontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder"
        let isCurrentClipboard = NSPasteboard.general.changeCount == payload.clipboardChangeCount
        guard isFinderFrontmost, isCurrentClipboard else {
            launchSmoke?.report("feedback-suppressed-finder-\(isFinderFrontmost)-clipboard-\(isCurrentClipboard)")
            if terminateAfterDisplay && !keepsClipboardSyncOwnerAlive {
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
        guard terminateAfterDisplay && !keepsClipboardSyncOwnerAlive else { return }
        feedbackHostTermination?.cancel()
        let termination = DispatchWorkItem { [weak self] in
            guard self?.keepsClipboardSyncOwnerAlive != true else { return }
            NSApp.terminate(nil)
        }
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
    func settingsViewController(_ controller: SettingsViewController, didChangeICloudSyncEnabled enabled: Bool) -> Bool {
        guard let settingsCoordinator else { return false }
        let old = settingsCoordinator.readClipboardICloudSyncEnabled()
        do {
            try settingsCoordinator.saveClipboardICloudSyncEnabled(enabled)
            if let clipboardSyncCoordinator { clipboardSyncCoordinator.apply(enabled: enabled) }
            else { controller.applyClipboardSync(enabled: enabled, state: .failed) }
        } catch {
            controller.restoreClipboardSyncAfterSaveFailure(enabled: old, state: clipboardSyncCoordinator?.state ?? .failed,
                pauseNeedsRetry: clipboardSyncCoordinator?.pauseNeedsRetry ?? false)
        }
        return true
    }

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
