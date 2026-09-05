import Foundation

/// Launching is kept behind a protocol so settings persistence can be tested
/// without starting a second application process.
protocol TidyTapHelperLaunching: AnyObject {
    func launchOrActivateHelper()
}

/// A completed ServiceManagement mutation could not be reconciled after the
/// preferences write failed. Both underlying failures are retained so the UI
/// can tell the user that login registration needs manual recovery.
struct TidyTapSettingsRecoveryRequiredError: Error {
    let persistenceError: Error
    let loginItemRecoveryError: Error
}

/// Coordinates a settings write with the only IPC contract the helper accepts:
/// a correlated request ID. It deliberately does not contain AppKit controls.
final class SettingsCoordinator {
    private let preferences: TidyTapPreferencesStoring
    private let helperLauncher: TidyTapHelperLaunching
    private let loginItemManager: TidyTapLoginItemManaging

    private(set) var latestRequestID: UUID?
    private(set) var latestApplyStatus: TidyTapApplyStatus?
    private var settingsBeforeLatestRequest: TidyTapSettings?

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
        latestRequestID = request.applyRequestID
        let status = preferences.readApplyStatus()
        latestApplyStatus = status?.applyRequestID == request.applyRequestID ? status : nil
        helperLauncher.launchOrActivateHelper()
    }

    func persistedSettings() -> TidyTapSettings {
        preferences.readRequest().settings
    }

    func settingsForUI() -> TidyTapSettings {
        let request = preferences.readRequest()
        let status = preferences.readApplyStatus()
        var settings = status?.applyRequestID == request.applyRequestID
            ? status?.effectiveSettings ?? request.settings
            : request.settings
        settings.launchAtLogin = loginItemManager.status() == .enabled
        return settings
    }

    func loginItemStatus() -> TidyTapLoginItemStatus { loginItemManager.status() }

    @discardableResult
    func save(_ settings: TidyTapSettings) throws -> UUID {
        let previousRequest = preferences.readRequest()
        let requestID = UUID()

        // ServiceManagement is the only external mutation in this transaction.
        // Do it before writing a new snapshot so a rejected register/unregister
        // request cannot be picked up by a future helper launch.
        try loginItemManager.setEnabled(settings.launchAtLogin)

        do {
            try preferences.write(settings: settings, applyRequestID: requestID)
        } catch let persistenceError {
            // A preferences failure must not leave the login registration out
            // of sync with the still-persisted snapshot.
            do {
                try loginItemManager.setEnabled(previousRequest.settings.launchAtLogin)
            } catch let loginItemRecoveryError {
                throw TidyTapSettingsRecoveryRequiredError(
                    persistenceError: persistenceError,
                    loginItemRecoveryError: loginItemRecoveryError
                )
            }
            throw persistenceError
        }

        latestRequestID = requestID
        latestApplyStatus = .pending(requestID)
        settingsBeforeLatestRequest = previousRequest.settings

        // All-off requests also launch the helper: a prior crash may have left
        // a durable Caps journal that only the helper can safely restore.
        helperLauncher.launchOrActivateHelper()
        TidyTapIPC.postSettingsDidChange(requestID: requestID)
        return requestID
    }

    /// Result notifications are intentionally correlation-gated. A stale
    /// helper result cannot make a newer UI toggle appear successful.
    @discardableResult
    func receiveApplyResult() -> TidyTapApplyStatus? {
        let request = preferences.readRequest()
        guard let status = preferences.readApplyStatus(),
              status.applyRequestID == request.applyRequestID else {
            return nil
        }
        latestRequestID = request.applyRequestID
        latestApplyStatus = status
        return status
    }

    /// A rejected helper request has already been restored by the helper. Keep
    /// the visible UI truthful without issuing a second settings submission.
    func visibleSettings(for status: TidyTapApplyStatus) -> TidyTapSettings {
        var settings: TidyTapSettings
        if let effective = status.effectiveSettings {
            settings = effective
        } else {
            switch status.outcome {
            case .failed, .recoveryRequired:
                settings = settingsBeforeLatestRequest ?? persistedSettings()
            case .pending, .applied, .partiallyApplied:
                settings = persistedSettings()
            }
        }
        settings.launchAtLogin = loginItemManager.status() == .enabled
        return settings
    }

    func permissionSettingsPane(for status: TidyTapApplyStatus) -> TidyTapPermission? {
        guard let code = status.errorCode else { return nil }
        if code.contains("permissionDenied.accessibility") ||
            code.contains("permissionPartial.accessibility") {
            return .accessibility
        }
        if code.contains("permissionDenied.inputMonitoring") ||
            code.contains("permissionPartial.inputMonitoring") {
            return .inputMonitoring
        }
        return nil
    }
}
