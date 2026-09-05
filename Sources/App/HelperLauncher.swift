import AppKit

final class HelperLauncher: TidyTapHelperLaunching {
    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func launchOrActivateHelper() {
        if let helper = workspace.runningApplications.first(where: {
            $0.bundleIdentifier == TidyTapProduct.helperBundleIdentifier
        }) {
            helper.activate()
            return
        }

        guard let helperURL = embeddedHelperURL() else {
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        workspace.openApplication(at: helperURL, configuration: configuration) { _, _ in }
    }

    private func embeddedHelperURL() -> URL? {
        guard let appURL = Bundle.main.bundleURL as URL? else {
            return nil
        }
        return appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Library")
            .appendingPathComponent("LoginItems")
            .appendingPathComponent("TidyTapHelper.app")
    }
}
