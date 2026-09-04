import Foundation

/// Launching is kept behind a protocol so settings persistence can be tested
/// without starting a second application process.
protocol TidyTapHelperLaunching: AnyObject {
    func launchOrActivateHelper()
}

/// Coordinates a settings write with the only IPC contract the helper accepts:
/// a correlated request ID. It deliberately does not contain AppKit controls.
final class SettingsCoordinator {
    private let preferences: TidyTapPreferencesStoring
    private let helperLauncher: TidyTapHelperLaunching
    private let loginItemManager: TidyTapLoginItemManaging

    private(set) var latestRequestID: UUID?
    private(set) var latestApplyStatus: TidyTapApplyStatus?

    init(
        preferences: TidyTapPreferencesStoring = TidyTapPreferencesStore(),
        helperLauncher: TidyTapHelperLaunching,
        loginItemManager: TidyTapLoginItemManaging = LoginItemCoordinator()
    ) {
        self.preferences = preferences
        self.helperLauncher = helperLauncher
        self.loginItemManager = loginItemManager
    }

    /// Reconciles persistent login registration and starts the helper when a
    /// saved feature needs it. Command-Q never calls a helper termination API.
    func restoreSession() {
        let request = preferences.readRequest()
        try? loginItemManager.setEnabled(request.settings.launchAtLogin)
        if request.settings.requiresHelper {
            helperLauncher.launchOrActivateHelper()
        }
    }

    @discardableResult
    func save(_ settings: TidyTapSettings) throws -> UUID {
        let requestID = UUID()
        try preferences.write(settings: settings, applyRequestID: requestID)
        try loginItemManager.setEnabled(settings.launchAtLogin)

        latestRequestID = requestID
        latestApplyStatus = .pending(requestID)

        // A running helper must receive an all-off request so it can restore
        // state and exit. If it is not running, no helper is necessary.
        if settings.requiresHelper {
            helperLauncher.launchOrActivateHelper()
        }
        TidyTapIPC.postSettingsDidChange(requestID: requestID)
        return requestID
    }

    /// Result notifications are intentionally correlation-gated. A stale
    /// helper result cannot make a newer UI toggle appear successful.
    @discardableResult
    func receiveApplyResult() -> TidyTapApplyStatus? {
        guard let expectedID = latestRequestID,
              let status = preferences.readApplyStatus(),
              status.applyRequestID == expectedID else {
            return nil
        }

        latestApplyStatus = status
        return status
    }
}
