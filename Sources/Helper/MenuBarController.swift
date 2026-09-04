@preconcurrency import AppKit

/// The helper owns the optional status item. Its menu intentionally has just
/// one action; feature controls remain in the Dock application's settings UI.
@MainActor
final class MenuBarController: NSObject, TidyTapMenuBarApplying {
    private var statusItem: NSStatusItem?
    var isMenuBarVisible: Bool { statusItem != nil }

    func applyMenuBar(visible: Bool) throws {
        if visible {
            installStatusItemIfNeeded()
        } else {
            removeStatusItem()
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = TidyTapStrings.appName

        let menu = NSMenu()
        let openItem = NSMenuItem(
            title: TidyTapStrings.openApp,
            action: #selector(openTidyTap),
            keyEquivalent: ""
        )
        openItem.target = self
        menu.addItem(openItem)
        item.menu = menu
        statusItem = item
    }

    private func removeStatusItem() {
        guard let statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    @objc private func openTidyTap() {
        guard let appURL = mainApplicationURL() else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { _, _ in }
    }

    private func mainApplicationURL() -> URL? {
        var url = Bundle.main.bundleURL
        for _ in 0..<4 {
            url.deleteLastPathComponent()
        }
        return url.pathExtension == "app" ? url : nil
    }
}
