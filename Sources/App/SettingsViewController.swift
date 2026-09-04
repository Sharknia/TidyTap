import AppKit

/// Stage 1 owns the Dock-app window only. The settings controls are added after
/// the corresponding helper capabilities exist.
final class SettingsViewController: NSViewController {
    override func loadView() {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        self.view = view
    }
}
