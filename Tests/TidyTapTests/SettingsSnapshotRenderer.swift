import AppKit
import Foundation

@MainActor
enum SettingsSnapshotRenderer {
    struct Fixture {
        let filename: String
        let language: String
        let settings: TidyTapSettings
        let permissions: TidyTapFeaturePermissionState
    }

    static let fixtures: [Fixture] = {
        var normal = TidyTapSettings.defaults
        normal.capsLockInputSourceSwitching = true

        return [
            Fixture(
                filename: "liquid-glass-normal.png",
                language: "ko",
                settings: normal,
                permissions: .init(accessibility: .authorized, inputMonitoring: .authorized)
            ),
            Fixture(
                filename: "liquid-glass-both-denied.png",
                language: "ko",
                settings: .defaults,
                permissions: .init(accessibility: .denied, inputMonitoring: .denied)
            ),
            Fixture(
                filename: "liquid-glass-ax-allowed-im-denied.png",
                language: "ko",
                settings: .defaults,
                permissions: .init(accessibility: .authorized, inputMonitoring: .denied)
            ),
            Fixture(
                filename: "liquid-glass-normal-en.png",
                language: "en",
                settings: normal,
                permissions: .init(accessibility: .authorized, inputMonitoring: .authorized)
            ),
            Fixture(
                filename: "liquid-glass-both-denied-en.png",
                language: "en",
                settings: .defaults,
                permissions: .init(accessibility: .denied, inputMonitoring: .denied)
            ),
            Fixture(
                filename: "liquid-glass-ax-allowed-im-denied-en.png",
                language: "en",
                settings: .defaults,
                permissions: .init(accessibility: .authorized, inputMonitoring: .denied)
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
            displayVersion: "0.1.0",
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
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = .windowBackgroundColor
        window.isOpaque = true
        let host = NSView(frame: NSRect(origin: .zero, size: size))
        host.appearance = NSAppearance(named: .aqua)
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        window.contentView = host
        controller.view.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(controller.view)
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
