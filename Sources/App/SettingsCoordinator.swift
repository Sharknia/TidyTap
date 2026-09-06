import Foundation

/// Launching is kept behind a protocol so settings persistence can be tested
/// without starting a second application process.
protocol TidyTapHelperLaunching: AnyObject {
    func ensureHelperRunning() throws
}

/// A user-initiated settings-pane request is consumed only by the helper
/// result that carries its exact request ID. Refreshes never create one.
struct TidyTapPendingPermissionSettingsOpen: Equatable {
    private var requestID: UUID?
    private let permission: TidyTapPermission

    init(requestID: UUID, permission: TidyTapPermission) {
        self.requestID = requestID
        self.permission = permission
    }

    mutating func consume(matching resultID: UUID) -> TidyTapPermission? {
        guard requestID == resultID else { return nil }
        requestID = nil
        return permission
    }

    /// An explicit click opens its exact pane after the matching helper result,
    /// even when the helper confirms that access is already granted.
    mutating func consume(matching result: TidyTapPermissionResult) -> TidyTapPermission? {
        consume(matching: result.requestID)
    }
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
    private(set) var latestPermissionRequestID: UUID?
    private(set) var latestPermissionState: TidyTapFeaturePermissionState?
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
        // Every settings launch gets a current worker snapshot, including a
        // fresh install or a previous successful run. Stored failures aren't
        // the authority for today's permission display.
        if (try? enqueuePermission(kind: .refresh, permission: nil)) != nil {
            return
        }
        try? helperLauncher.ensureHelperRunning()
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
        try helperLauncher.ensureHelperRunning()
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
        applyExplicitPermissionDowngrade(from: status)
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
        let unavailable = unavailablePermissions(in: status)
        if unavailable.contains(.accessibility) {
            return .accessibility
        }
        if unavailable.contains(.inputMonitoring) {
            return .inputMonitoring
        }
        return nil
    }

    /// The System Settings deep links are intentionally a pure mapping so it
    /// can be tested without opening a user-facing settings pane.
    static func permissionSettingsURL(for permission: TidyTapPermission) -> URL {
        switch permission {
        case .accessibility:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        case .inputMonitoring:
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        }
    }

    /// Each foreground return reads the worker's current state without prompts.
    @discardableResult
    func refreshPermissionsIfNeeded() throws -> UUID? {
        guard latestPermissionRequestID == nil else {
            return nil
        }
        return try enqueuePermission(kind: .refresh, permission: nil)
    }

    @discardableResult
    func requestPermission(_ permission: TidyTapPermission) throws -> UUID {
        try enqueuePermission(kind: .request, permission: permission)
    }

    func receivePermissionResult() -> TidyTapPermissionResult? {
        guard let currentID = latestPermissionRequestID,
              let request = preferences.readPermissionRequest(), request.requestID == currentID,
              let result = preferences.readPermissionResult(), result.requestID == currentID else {
            return nil
        }
        latestPermissionRequestID = nil
        latestPermissionState = result.state
        return result
    }

    func permissionSettingsPane(
        for status: TidyTapApplyStatus,
        confirmed state: TidyTapFeaturePermissionState
    ) -> TidyTapPermission? {
        let unavailable = unavailablePermissions(in: status)
        if unavailable.contains(.accessibility), state.accessibility != .authorized {
            return .accessibility
        }
        if unavailable.contains(.inputMonitoring), state.inputMonitoring != .authorized {
            return .inputMonitoring
        }
        return nil
    }

    private func unavailablePermissions(in status: TidyTapApplyStatus) -> Set<TidyTapPermission> {
        guard status.failedComponent == .eventTap,
              let code = status.errorCode,
              code.hasPrefix("eventTap.permissionDenied.") ||
                code.hasPrefix("eventTap.permissionPartial.") else {
            return []
        }
        return Set(TidyTapPermission.allCases.filter { code.split(separator: ".").contains(Substring($0.rawValue)) })
    }

    /// A permission failure is affirmative helper evidence for only the names
    /// encoded in its stable error code. Unmentioned permissions stay unchanged
    /// (or unknown); success never implies authorization.
    private func applyExplicitPermissionDowngrade(from status: TidyTapApplyStatus) {
        let unavailable = unavailablePermissions(in: status)
        guard !unavailable.isEmpty else { return }
        var state = latestPermissionState ?? .init()
        if unavailable.contains(.accessibility) {
            state.accessibility = .denied
        }
        if unavailable.contains(.inputMonitoring) {
            state.inputMonitoring = .denied
        }
        latestPermissionState = state
    }

    private func enqueuePermission(
        kind: TidyTapPermissionRequestKind,
        permission: TidyTapPermission?
    ) throws -> UUID {
        let request = TidyTapPermissionRequest(
            requestID: UUID(),
            kind: kind,
            permission: permission
        )
        try preferences.writePermissionRequest(request)
        latestPermissionRequestID = request.requestID
        try helperLauncher.ensureHelperRunning()
        TidyTapIPC.postPermissionRequest(request)
        return request.requestID
    }
}
