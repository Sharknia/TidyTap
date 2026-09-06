import Foundation

final class HelperLauncher: TidyTapHelperLaunching {
    func ensureHelperRunning() throws {
        let process = Process()
        process.executableURL = Bundle.main.bundleURL
            .appendingPathComponent(TidyTapProduct.helperExecutablePath)
        // A process-lifetime lock in the worker makes concurrent launches safe.
        // No separate app bundle or activation changes its TCC owner.
        try process.run()
    }
}
