import AppKit
import ApplicationServices
import TidyTapInputEngine

/// A background-only helper. It owns the process lifetime and applies the
/// complete persisted snapshot at launch and after each change notification.
@MainActor
final class HelperRuntime: NSObject {
    private var lifecycle: HelperLifecycle?
    private var clipboardProbeHotkey: ClipboardProbeHotkey?
    private var clipboardCaptureHost: HelperClipboardCaptureHost?
    private let launchSmoke = TidyTapLaunchSmoke.current()
    private var markReadiness: ((TidyTapWorkerLockOwner.Readiness) -> Bool)?

    @objc private func prepareForUpdate(_ notification: Notification) {
        guard markReadiness?(.stopping) == true else { return }
        stop()
        CFRunLoopStop(CFRunLoopGetMain())
    }

    @objc private func otherTidyTapDidLaunch(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == TidyTapProduct.appBundleIdentifier,
              let url = app.bundleURL,
              !TidyTapProduct.isInstalledCopy(url) else { return }
        stop()
        CFRunLoopStop(CFRunLoopGetMain())
    }

    private func startBackgroundUpdateHost() {
        let appURL = Bundle.main.bundleURL
        guard !NSRunningApplication.runningApplications(withBundleIdentifier: TidyTapProduct.appBundleIdentifier)
            .contains(where: { $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath() ==
                appURL.standardizedFileURL.resolvingSymlinksInPath() }) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        configuration.addsToRecentItems = false
        configuration.allowsRunningApplicationSubstitution = false
        configuration.environment = [TidyTapProduct.backgroundUpdateEnvironmentKey: "1"]
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
    }

    func start(setReadiness: @escaping (TidyTapWorkerLockOwner.Readiness) -> Bool = { _ in true }) {
        markReadiness = setReadiness
        if ProcessInfo.processInfo.environment["TIDYTAP_CLIPBOARD_G1_PROBE"] == "1" {
            guard let launchSmoke else { exit(1) }
            do {
                let store = try ClipboardHistoryStore(
                    directory: TidyTapProduct.clipboardHistoryDirectory(preferencesSuite: launchSmoke.preferencesSuite),
                    retention: TidyTapClipboardPolicy.retention,
                    maximumEntries: TidyTapClipboardPolicy.maximumEntries,
                    maximumBytes: TidyTapClipboardPolicy.maximumBytes,
                    maximumItemBytes: TidyTapClipboardPolicy.maximumItemBytes
                )
                if try store.entries().isEmpty {
                    if ProcessInfo.processInfo.environment["TIDYTAP_CLIPBOARD_G2_MEDIA_PROBE"] == "1" {
                        try seedClipboardMediaProbe(in: store)
                    } else {
                        try store.add(.text(plain: "TidyTap G2 test text", rtf: nil, html: nil))
                    }
                }
                FileHandle.standardError.write(Data("clipboard-g1: prepared entries=\(try store.entries().count)\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("clipboard-g1: could not prepare isolated test entry\n".utf8))
                exit(1)
            }
            let hotkey = ClipboardProbeHotkey()
            guard hotkey.start() else {
                FileHandle.standardError.write(Data("clipboard-g1: shortcut tap unavailable\n".utf8))
                exit(1)
            }
            let permissions = CGInputPermissionChecker()
            FileHandle.standardError.write(Data("clipboard-g1: shortcut tap active post=\(permissions.accessibilityAllowed) listen=\(permissions.inputMonitoringAllowed) axTrusted=\(AXIsProcessTrusted())\n".utf8))
            clipboardProbeHotkey = hotkey
            return
        }
        if ProcessInfo.processInfo.environment["TIDYTAP_CLIPBOARD_G3_PROBE"] == "1" {
            guard let launchSmoke else { exit(1) }
            let directory = TidyTapProduct.clipboardHistoryDirectory(preferencesSuite: launchSmoke.preferencesSuite)
            do {
                let store = try ClipboardHistoryStore(
                    directory: directory,
                    retention: TidyTapClipboardPolicy.retention,
                    maximumEntries: TidyTapClipboardPolicy.maximumEntries,
                    maximumBytes: TidyTapClipboardPolicy.maximumBytes,
                    maximumItemBytes: TidyTapClipboardPolicy.maximumItemBytes
                )
                FileHandle.standardError.write(Data("clipboard-g3: existing entries=\(try store.entries().count)\n".utf8))
                if #available(macOS 26.0, *) {
                    FileHandle.standardError.write(Data("clipboard-g3: access before=\(NSPasteboard.general.accessBehavior)\n".utf8))
                }
                var capturedCount = 0
                let host = HelperClipboardCaptureHost(directory: directory, onCaptured: {
                    capturedCount += 1
                    guard let entry = try? store.entries().first else { return }
                    let summary: String
                    switch entry.content {
                    case .text(let plain, let rtf, let html):
                        summary = "text bytes=\(plain.utf8.count) rtf=\(rtf != nil) html=\(html != nil)"
                    case .image(let data, let type):
                        summary = "image type=\(type.rawValue) bytes=\(data.count)"
                    }
                    FileHandle.standardError.write(Data("clipboard-g3: captured #\(capturedCount) \(summary)\n".utf8))
                })
                host.onFailure = { code in
                    FileHandle.standardError.write(Data("clipboard-g3: stopped reason=\(code)\n".utf8))
                }
                try host.apply(enabled: true)
                clipboardCaptureHost = host
                let hotkey = ClipboardProbeHotkey()
                guard hotkey.start() else {
                    host.stop()
                    FileHandle.standardError.write(Data("clipboard-g3: shortcut tap unavailable\n".utf8))
                    exit(1)
                }
                clipboardProbeHotkey = hotkey
                if #available(macOS 26.0, *) {
                    FileHandle.standardError.write(Data("clipboard-g3: access after=\(NSPasteboard.general.accessBehavior)\n".utf8))
                }
                FileHandle.standardError.write(Data("clipboard-g3: monitor active\n".utf8))
            } catch {
                FileHandle.standardError.write(Data("clipboard-g3: monitor unavailable reason=\(error)\n".utf8))
                exit(1)
            }
            return
        }
        let preferences: TidyTapPreferencesStore
        let capsFeature: TidyTapCapsFeatureApplying
        let inputFeatures: TidyTapInputFeaturesApplying
        let menuBar: TidyTapMenuBarApplying
        let settingsProbe = launchSmoke != nil &&
            ProcessInfo.processInfo.environment["TIDYTAP_CLIPBOARD_SETTINGS_PROBE"] == "1"

        if let launchSmoke {
            preferences = TidyTapPreferencesStore(defaults: launchSmoke.makePreferences())
            capsFeature = LaunchSmokeCapsFeature(smoke: launchSmoke)
            inputFeatures = settingsProbe ? InputFeaturesAdapter() : LaunchSmokeInputFeatures(smoke: launchSmoke)
            menuBar = LaunchSmokeMenuBar(smoke: launchSmoke)
        } else {
            preferences = TidyTapPreferencesStore()
            capsFeature = CapsLockFeatureAdapter(
                system: MacOSSystemApplyAdapter(),
                ownershipStore: preferences
            )
            inputFeatures = InputFeaturesAdapter()
            menuBar = MenuBarController()
        }

        let deniedReadState: (() -> HelperClipboardCaptureHost.ReadState)? =
            settingsProbe && ProcessInfo.processInfo.environment["TIDYTAP_CLIPBOARD_SETTINGS_PROBE_DENY"] == "1"
                ? { .denied } : nil
        let captureHost: HelperClipboardCaptureHost? = launchSmoke == nil || settingsProbe
            ? HelperClipboardCaptureHost(
                directory: TidyTapProduct.clipboardHistoryDirectory(
                    preferencesSuite: launchSmoke?.preferencesSuite ?? TidyTapProduct.appBundleIdentifier
                ),
                onCaptured: TidyTapIPC.postClipboardHistoryChanged,
                readState: deniedReadState
            )
            : nil
        let coordinator = ApplyCoordinator(
            preferences: preferences,
            capsFeature: capsFeature,
            inputFeatures: inputFeatures,
            menuBar: menuBar,
            terminator: settingsProbe ? SettingsProbeTerminator() : ApplicationTerminator(setReadiness: setReadiness),
            clipboardPreflight: { enabled in
                _ = try captureHost?.prepare(enabled: enabled)
            }
        )
        captureHost?.onFailure = { [weak coordinator] code in
            coordinator?.reportClipboardCaptureFailure(code: code)
        }
        clipboardCaptureHost = captureHost
        if let productionInputFeatures = inputFeatures as? InputFeaturesAdapter {
            productionInputFeatures.runtimeStatusHandler = { [weak coordinator] requestID, result, error in
                DispatchQueue.main.async {
                    coordinator?.reportRuntimeInput(requestID: requestID, result, error: error)
                }
            }
        }
        let lifecycle = HelperLifecycle(
            coordinator: coordinator,
            permissionCoordinator: HelperPermissionCoordinator(preferences: preferences),
            afterApply: { [weak captureHost, weak coordinator] status in
                guard let captureHost else { return }
                do {
                    try captureHost.apply(enabled: status.effectiveSettings?.clipboardHistoryEnabled == true)
                } catch {
                    captureHost.stop()
                    let code: String
                    if let access = error as? ClipboardCaptureService.CaptureError {
                        switch access {
                        case .readDenied: code = "clipboardHistory.readDenied"
                        case .continuousAccessRequired: code = "clipboardHistory.continuousAccessRequired"
                        }
                    } else {
                        code = "clipboardHistory.storageFailed"
                    }
                    coordinator?.reportClipboardCaptureFailure(
                        code: code
                    )
                }
            }
        )
        self.lifecycle = lifecycle
        lifecycle.start()
        let updateStopProbe = launchSmoke != nil &&
            ProcessInfo.processInfo.environment["TIDYTAP_UPDATE_STOP_PROBE"] == "1"
        if launchSmoke == nil || updateStopProbe {
            DistributedNotificationCenter.default().addObserver(
                self,
                selector: #selector(prepareForUpdate(_:)),
                name: TidyTapIPC.prepareForUpdate,
                object: launchSmoke?.preferencesSuite ?? TidyTapProduct.appBundleIdentifier,
                suspensionBehavior: .deliverImmediately
            )
        }
        if launchSmoke == nil {
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(otherTidyTapDidLaunch(_:)),
                name: NSWorkspace.didLaunchApplicationNotification,
                object: nil
            )
            startBackgroundUpdateHost()
        }
        launchSmoke?.report("helper-delegate-started")
    }

    func stop() {
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        clipboardProbeHotkey?.stop()
        clipboardCaptureHost?.stop()
        lifecycle?.stop()
    }

    private func seedClipboardMediaProbe(in store: ClipboardHistoryStore) throws {
        let now = Date()
        try store.add(.text(plain: "TidyTap G2 plain text", rtf: nil, html: nil), copiedAt: now.addingTimeInterval(-2))
        let bold = NSAttributedString(
            string: "TidyTap G2 bold text",
            attributes: [.font: NSFont.boldSystemFont(ofSize: 22), .foregroundColor: NSColor.systemRed]
        )
        let rtf = try bold.data(
            from: NSRange(location: 0, length: bold.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let html = Data("<span style=\"font-weight:700;color:#ff0000\">TidyTap G2 bold text</span>".utf8)
        try store.add(.text(plain: bold.string, rtf: rtf, html: html), copiedAt: now.addingTimeInterval(-1))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 48, pixelsHigh: 48,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ) else { throw ClipboardHistoryStore.StoreError.invalidPolicy }
        let orange = NSColor(deviceRed: 1, green: 0.45, blue: 0, alpha: 1)
        let blue = NSColor(deviceRed: 0, green: 0.35, blue: 1, alpha: 1)
        for x in 0..<48 {
            for y in 0..<48 {
                bitmap.setColor(x < 24 ? orange : blue, atX: x, y: y)
            }
        }
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw ClipboardHistoryStore.StoreError.invalidPolicy
        }
        try store.add(.image(data: png, type: .png), copiedAt: now)
    }
}

@MainActor
private final class SettingsProbeTerminator: TidyTapTerminating {
    func terminate() {}
}

/// Temporary, opt-in G1 probe. It uses the product input backend and never reads the pasteboard.
private final class ClipboardProbeHotkey: @unchecked Sendable {
    private let backend = CGEventTapBackend(clipboardShortcutHandler: {
        FileHandle.standardError.write(Data("clipboard-g1: hotkey matched\n".utf8))
        ClipboardHistoryAppHost.present()
    })

    func start() -> Bool {
        do {
            try backend.install(
                configuration: .init(
                    reverseMouseScroll: false,
                    sideButtonNavigation: false,
                    clipboardShortcut: .init(keyCode: 8, modifiers: CGEventFlags.maskAlternate.rawValue)
                ),
                captureSideButtons: false,
                handler: { _ in .passThrough }
            )
            return true
        } catch {
            let permissions = CGInputPermissionChecker()
            FileHandle.standardError.write(Data(
                "clipboard-g1: tap unavailable post=\(permissions.accessibilityAllowed) listen=\(permissions.inputMonitoringAllowed) error=\(error)\n".utf8
            ))
            return false
        }
    }

    func stop() {
        backend.uninstall()
    }
}

private final class LaunchSmokeCapsFeature: TidyTapCapsFeatureApplying {
    private let smoke: TidyTapLaunchSmoke
    private var enabled = false

    init(smoke: TidyTapLaunchSmoke) {
        self.smoke = smoke
    }

    func apply(capsLockEnabled: Bool) throws {
        enabled = capsLockEnabled
        smoke.report("helper-caps-\(capsLockEnabled ? "enabled" : "disabled")")
    }

    func currentCapsLockEnabled() throws -> Bool {
        enabled
    }
}

private final class LaunchSmokeInputFeatures: TidyTapInputFeaturesApplying {
    private let smoke: TidyTapLaunchSmoke
    private var configuration = TidyTapInputFeatureConfiguration.disabled

    init(smoke: TidyTapLaunchSmoke) {
        self.smoke = smoke
    }

    func apply(
        reverseMouseWheel: Bool,
        sideButtonNavigation: Bool,
        fixedMouseWheelStepEnabled: Bool,
        finderCutPasteEnabled: Bool,
        clipboardShortcut: TidyTapClipboardShortcut?,
        mouseWheelStepLines: Int,
        requestID: UUID
    ) throws -> TidyTapInputFeatureApplyResult {
        configuration = TidyTapInputFeatureConfiguration(
            reverseMouseWheel: reverseMouseWheel,
            sideButtonNavigation: sideButtonNavigation,
            fixedMouseWheelStepEnabled: fixedMouseWheelStepEnabled,
            finderCutPasteEnabled: finderCutPasteEnabled,
            clipboardShortcut: clipboardShortcut,
            mouseWheelStepLines: mouseWheelStepLines
        )
        smoke.report(
            "helper-input-\(reverseMouseWheel ? "wheel-on" : "wheel-off")-" +
                "\(sideButtonNavigation ? "buttons-on" : "buttons-off")-" +
                "\(fixedMouseWheelStepEnabled ? "step-on" : "step-off")-" +
                "lines-\(mouseWheelStepLines)"
        )
        return .applied
    }

    func forcePassThrough() throws {
        configuration = .init(
            reverseMouseWheel: false,
            sideButtonNavigation: false,
            fixedMouseWheelStepEnabled: false,
            finderCutPasteEnabled: false,
            clipboardShortcut: nil,
            mouseWheelStepLines: configuration.mouseWheelStepLines
        )
    }

    func currentConfiguration() -> TidyTapInputFeatureConfiguration {
        configuration
    }
}

@MainActor
private final class LaunchSmokeMenuBar: TidyTapMenuBarApplying {
    private let smoke: TidyTapLaunchSmoke
    private(set) var isMenuBarVisible = false

    init(smoke: TidyTapLaunchSmoke) {
        self.smoke = smoke
    }

    func applyMenuBar(visible: Bool) throws {
        isMenuBarVisible = visible
        smoke.report("helper-menu-\(visible ? "visible" : "hidden")")
    }
}
