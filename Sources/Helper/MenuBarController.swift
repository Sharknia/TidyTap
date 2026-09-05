@preconcurrency import AppKit

/// Compatibility adapter retained so the helper transaction and launch smoke
/// keep their stable seam after the menu-bar feature was retired.
@MainActor
final class MenuBarController: NSObject, TidyTapMenuBarApplying {
    var isMenuBarVisible: Bool { false }

    func applyMenuBar(visible: Bool) throws {
        // Intentionally no-op. `visible` is accepted for migration-safe calls
        // from older snapshots but never creates a status item.
    }
}
