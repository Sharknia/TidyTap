import AppKit
import Foundation
import TidyTapInputEngine

@MainActor
enum SettingsSnapshotRenderer {
    struct Fixture {
        let filename: String
        let language: String
        let settings: TidyTapSettings
        let permissions: TidyTapFeaturePermissionState
        let appearance: NSAppearance.Name
        var applyStatus: TidyTapApplyStatus? = nil
    }

    static let fixtures: [Fixture] = {
        var normal = TidyTapSettings.defaults
        normal.capsLockInputSourceSwitching = true
        normal.fixedMouseWheelStepEnabled = true
        normal.mouseWheelStepLines = 7
        var clipboard = TidyTapSettings.defaults
        clipboard.clipboardHistoryEnabled = true
        clipboard.clipboardHistoryShortcut = .init(
            keyCode: 8, modifiers: CGEventFlags.maskAlternate.rawValue, displayKey: "C"
        )

        return [
            Fixture(
                filename: "clipboard-enabled-ko.png", language: "ko", settings: clipboard,
                permissions: .init(accessibility: .authorized, inputMonitoring: .authorized), appearance: .aqua
            ),
            Fixture(
                filename: "clipboard-enabled-en-dark.png", language: "en", settings: clipboard,
                permissions: .init(accessibility: .authorized, inputMonitoring: .authorized), appearance: .darkAqua
            ),
            Fixture(filename: "caps-read-failure-ko.png", language: "ko", settings: .defaults,
                permissions: .init(accessibility: .authorized, inputMonitoring: .authorized), appearance: .aqua,
                applyStatus: .init(applyRequestID: UUID(), outcome: .failed, failedComponent: .capsLock,
                    errorCode: "capsLock.invalidSystemData.hidMappings")),
            Fixture(filename: "caps-conflict-en.png", language: "en", settings: .defaults,
                permissions: .init(accessibility: .authorized, inputMonitoring: .authorized), appearance: .aqua,
                applyStatus: .init(applyRequestID: UUID(), outcome: .failed, failedComponent: .capsLock,
                    errorCode: "capsLock.conflict.sourceMapping")),
            Fixture(
                filename: "liquid-glass-normal.png",
                language: "ko",
                settings: normal,
                permissions: .init(accessibility: .authorized, inputMonitoring: .authorized),
                appearance: .aqua
            ),
            Fixture(
                filename: "liquid-glass-accessibility-denied.png",
                language: "ko",
                settings: .defaults,
                permissions: .init(accessibility: .denied, inputMonitoring: .denied),
                appearance: .aqua
            ),
            Fixture(
                filename: "liquid-glass-ax-allowed-im-denied.png",
                language: "ko",
                settings: .defaults,
                permissions: .init(accessibility: .authorized, inputMonitoring: .denied),
                appearance: .aqua
            ),
            Fixture(
                filename: "liquid-glass-normal-en.png",
                language: "en",
                settings: normal,
                permissions: .init(accessibility: .authorized, inputMonitoring: .authorized),
                appearance: .aqua
            ),
            Fixture(
                filename: "liquid-glass-accessibility-denied-en.png",
                language: "en",
                settings: .defaults,
                permissions: .init(accessibility: .denied, inputMonitoring: .denied),
                appearance: .aqua
            ),
            Fixture(
                filename: "liquid-glass-ax-allowed-im-denied-en.png",
                language: "en",
                settings: .defaults,
                permissions: .init(accessibility: .authorized, inputMonitoring: .denied),
                appearance: .aqua
            ),
            Fixture(
                filename: "wheel-step-off-ko-light.png",
                language: "ko",
                settings: .defaults,
                permissions: .init(accessibility: .authorized, inputMonitoring: .authorized),
                appearance: .aqua
            ),
            Fixture(
                filename: "wheel-step-off-en-light.png",
                language: "en",
                settings: .defaults,
                permissions: .init(accessibility: .authorized, inputMonitoring: .authorized),
                appearance: .aqua
            ),
            Fixture(
                filename: "wheel-step-off-ko-dark.png",
                language: "ko",
                settings: .defaults,
                permissions: .init(accessibility: .authorized, inputMonitoring: .authorized),
                appearance: .darkAqua
            ),
            Fixture(
                filename: "wheel-step-on-ko-dark.png",
                language: "ko",
                settings: normal,
                permissions: .init(accessibility: .authorized, inputMonitoring: .authorized),
                appearance: .darkAqua
            ),
            Fixture(
                filename: "wheel-step-off-en-dark.png",
                language: "en",
                settings: .defaults,
                permissions: .init(accessibility: .authorized, inputMonitoring: .authorized),
                appearance: .darkAqua
            ),
            Fixture(
                filename: "wheel-step-on-en-dark.png",
                language: "en",
                settings: normal,
                permissions: .init(accessibility: .authorized, inputMonitoring: .authorized),
                appearance: .darkAqua
            )
        ]
    }()

    /// Uses a borderless host window only to establish AppKit backing and
    /// appearance. The window is never made key, ordered, or shown.
    static func render(_ fixture: Fixture, to outputURL: URL) throws {
        _ = NSApplication.shared
        let controller = SettingsViewController(
            settings: fixture.settings,
            permissionState: fixture.permissions,
            appIcon: NSImage(contentsOf: sourceRoot.appendingPathComponent("Resources/TidyTap.icns")),
            displayVersion: "0.3.0",
            renderingMode: .offscreenSemanticFallback,
            localizationBundle: localizedBundle(language: fixture.language)
        )
        let size = SettingsViewController.contentSize
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: fixture.appearance)
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.appearance = NSAppearance(named: fixture.appearance)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.contentView = host
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(controller.view)
        if let status = fixture.applyStatus {
            controller.showApplyStatus(status)
        }
        NSLayoutConstraint.activate([
            controller.view.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            controller.view.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            controller.view.topAnchor.constraint(equalTo: host.topAnchor),
            controller.view.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        host.layoutSubtreeIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()

        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            throw SnapshotError.bitmapUnavailable
        }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            throw SnapshotError.pngEncodingFailed
        }
        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: outputURL, options: .atomic)
    }

    private static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    static func renderClipboardScenes(to directory: URL) throws -> [URL] {
        struct Fixture: Encodable { let id: UUID; let copiedAt: Date; let content: ClipboardCapturedContent }
        func entry(_ content: ClipboardCapturedContent) throws -> ClipboardHistoryEntry {
            try PropertyListDecoder().decode(ClipboardHistoryEntry.self,
                from: PropertyListEncoder().encode(Fixture(id: UUID(), copiedAt: Date(), content: content)))
        }
        let h = try entry(.text(plain: "프로젝트 안내 · Project note", rtf: nil, html: nil))
        let p = try entry(.text(plain: "자주 쓰는 안내 문구 · Reusable text", rtf: nil, html: nil))
        let image = try entry(.image(data: NSImage(systemSymbolName: "photo", accessibilityDescription: nil)?.tiffRepresentation ?? Data(), type: .tiff))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var files = [URL]()
        for language in ["ko", "en"] {
            for width in [480, 800] {
                for scene in ["history", "pinned", "image", "empty", "errors"] {
                    let panel = ClipboardHistoryPanelController(localizationBundle: localizedBundle(language: language))
                    let snapshot = ClipboardLibrarySnapshot(entries: [h,p,image], historyOrder: [h.id,image.id], pinnedOrder: [p.id,image.id])
                    panel.updateEntries(snapshot)
                    if scene != "history" { _ = panel.switchPane(.pinned) }
                    if scene == "image" {
                        panel.refreshPreservingSelection(.init(entries: [image], historyOrder: [], pinnedOrder: [image.id]))
                    }
                    if scene == "empty" { panel.updateEntries(.init(entries: [], historyOrder: [], pinnedOrder: [])) }
                    if scene == "errors" {
                        panel.setPreviousAttempt("Paste failed · 붙여넣기 실패")
                        panel.refreshPreservingSelection(.init(entries: [h,h], historyOrder: [h.id], pinnedOrder: []))
                    }
                    panel.panel.appearance = NSAppearance(named: .darkAqua)
                    panel.panel.setContentSize(NSSize(width: width, height: 360))
                    guard let view = panel.panel.contentView else { throw SnapshotError.bitmapUnavailable }
                    view.layoutSubtreeIfNeeded()
                    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { throw SnapshotError.bitmapUnavailable }
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    guard let png = bitmap.representation(using: .png, properties: [:]) else { throw SnapshotError.pngEncodingFailed }
                    let url = directory.appendingPathComponent("clipboard-\(language)-\(width)-\(scene).png")
                    try png.write(to: url); files.append(url)
                }
            }
        }
        try Data("AppKit offscreen bitmap; not an installed-device acceptance\n".utf8)
            .write(to: directory.appendingPathComponent("rendering-mode.txt"))
        return files
    }

    private static func localizedBundle(language: String) -> Bundle {
        let resources = Bundle(for: SnapshotBundleToken.self)
        guard let path = resources.path(forResource: language, ofType: "lproj"),
              let localized = Bundle(path: path) else {
            return resources
        }
        return localized
    }

    private enum SnapshotError: Error {
        case bitmapUnavailable
        case pngEncodingFailed
    }
}

private final class SnapshotBundleToken: NSObject {}
