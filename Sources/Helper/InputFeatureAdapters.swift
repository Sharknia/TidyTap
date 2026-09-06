import TidyTapInputEngine
import Foundation
import CoreGraphics

protocol TidyTapPermissionProviding: AnyObject {
    func currentState() -> TidyTapFeaturePermissionState
    func request(_ permission: TidyTapPermission)
}

final class CGTidyTapPermissionProvider: TidyTapPermissionProviding {
    func currentState() -> TidyTapFeaturePermissionState {
        TidyTapFeaturePermissionState(
            accessibility: CGPreflightPostEventAccess() ? .authorized : .denied,
            inputMonitoring: CGPreflightListenEventAccess() ? .authorized : .denied
        )
    }

    func request(_ permission: TidyTapPermission) {
        switch permission {
        case .accessibility:
            _ = CGRequestPostEventAccess()
        case .inputMonitoring:
            _ = CGRequestListenEventAccess()
        }
    }
}

/// Handles only the app/helper permission handshake. It never applies feature
/// settings, changes the Caps journal, or starts an event tap.
final class HelperPermissionCoordinator {
    private let preferences: TidyTapPreferencesStoring
    private let provider: TidyTapPermissionProviding
    private var applyStatusBeforeRequest: TidyTapApplyStatus?

    init(
        preferences: TidyTapPreferencesStoring,
        provider: TidyTapPermissionProviding = CGTidyTapPermissionProvider()
    ) {
        self.preferences = preferences
        self.provider = provider
    }

    @discardableResult
    func handleLatestRequest() -> TidyTapPermissionResult? {
        applyStatusBeforeRequest = preferences.readApplyStatus()
        guard let request = preferences.readPermissionRequest() else { return nil }
        if let existing = preferences.readPermissionResult(), existing.requestID == request.requestID {
            return existing
        }

        var state = provider.currentState()
        if request.kind == .request, let permission = request.permission,
           !state.isAuthorized(permission) {
            provider.request(permission)
            state = provider.currentState()
        }

        let result = TidyTapPermissionResult(requestID: request.requestID, state: state)
        _ = try? preferences.writePermissionResult(result)
        TidyTapIPC.postPermissionResult(result)
        return result
    }

    /// An all-off startup still applies controller cleanup, but that successful
    /// cleanup must not replace an unresolved permission result for the same
    /// already-sanitized settings generation.
    @discardableResult
    func restoreOutstandingPermissionFailure(
        after result: TidyTapPermissionResult?,
        startupApply: TidyTapApplyStatus
    ) -> TidyTapApplyStatus? {
        defer { applyStatusBeforeRequest = nil }
        guard let prior = applyStatusBeforeRequest,
              startupApply.outcome == .applied,
              startupApply.applyRequestID == prior.applyRequestID,
              prior.failedComponent == .eventTap,
              let priorCode = prior.errorCode,
              priorCode.hasPrefix("eventTap.permissionDenied.") ||
                priorCode.hasPrefix("eventTap.permissionPartial."),
              let result else {
            return nil
        }

        let unavailable = TidyTapPermission.allCases.filter { permission in
            priorCode.split(separator: ".").contains(Substring(permission.rawValue)) &&
                !result.state.isAuthorized(permission)
        }
        guard !unavailable.isEmpty else { return nil }

        let prefix = prior.outcome == .failed
            ? "eventTap.permissionDenied"
            : "eventTap.permissionPartial"
        let preserved = TidyTapApplyStatus(
            applyRequestID: prior.applyRequestID,
            outcome: prior.outcome,
            failedComponent: prior.failedComponent,
            errorCode: "\(prefix).\(unavailable.map(\.rawValue).sorted().joined(separator: "."))",
            effectiveSettings: prior.effectiveSettings
        )
        guard (try? preferences.writeApplyStatus(preserved)) != nil else { return nil }
        TidyTapIPC.postApplyResult(preserved)
        return preserved
    }
}

private extension TidyTapFeaturePermissionState {
    func isAuthorized(_ permission: TidyTapPermission) -> Bool {
        switch permission {
        case .accessibility: accessibility == .authorized
        case .inputMonitoring: inputMonitoring == .authorized
        }
    }
}

/// Error values are deliberately stable and small: they cross the helper/UI
/// boundary only through `TidyTapApplyStatus.errorCode`, never as raw system
/// errors or command output.
enum TidyTapInputFeatureAdapterError: Error {
    case permissionDenied(Set<TidyTapPermission>)
    case eventTapFailed
}

enum CapsJournalPhase: String, Codable { case prepared, applied }
struct CapsJournal: Codable {
    let enabled: Bool
    let phase: CapsJournalPhase
    let ownership: CapsLockFeatureOwnership
    let enablePlan: CapsLockEnablePlan?

    init(
        enabled: Bool,
        phase: CapsJournalPhase,
        ownership: CapsLockFeatureOwnership,
        enablePlan: CapsLockEnablePlan? = nil
    ) {
        self.enabled = enabled
        self.phase = phase
        self.ownership = ownership
        self.enablePlan = enablePlan
    }
}

final class CapsLockFeatureAdapter: TidyTapCapsFeatureApplying {
    private let controller: CapsLockFeatureController
    private let ownershipStore: TidyTapCapsOwnershipStoring
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    convenience init(system: MacOSSystemApplyAdapter, ownershipStore: TidyTapCapsOwnershipStoring) {
        self.init(controller: CapsLockFeatureController(
            hid: CapsLockController(system: system),
            hotkey: InputSourceShortcutController(system: system),
            inputSources: system
        ), ownershipStore: ownershipStore)
    }

    init(controller: CapsLockFeatureController, ownershipStore: TidyTapCapsOwnershipStoring) {
        self.controller = controller
        self.ownershipStore = ownershipStore
    }

    func apply(capsLockEnabled: Bool) throws {
        if capsLockEnabled {
            if let journal = try readJournal() {
                if journal.enabled {
                    if journal.phase == .prepared, let plan = journal.enablePlan {
                        let ownership = try controller.completePreparedEnable(plan)
                        try writeJournal(.init(enabled: true, phase: .applied, ownership: ownership))
                        return
                    }
                    if try controller.isApplied(journal.ownership) {
                        if journal.phase == .prepared {
                            try writeJournal(.init(enabled: true, phase: .applied, ownership: journal.ownership))
                        }
                        return
                    }
                    try controller.recoverHIDAfterReset(ownership: journal.ownership)
                    try writeJournal(.init(enabled: true, phase: .applied, ownership: journal.ownership))
                    return
                }
                try controller.restoreOwnedState(ownership: journal.ownership)
                try writeJournal(.init(enabled: true, phase: .applied, ownership: journal.ownership))
                return
            }
            let plan = try controller.prepareEnablePlan()
            guard let preparedOwnership = plan.ownership else {
                throw TransactionFailure(primaryDescription: "missing ownership after prepare")
            }
            try writeJournal(.init(
                enabled: true,
                phase: .prepared,
                ownership: preparedOwnership,
                enablePlan: plan
            ))
            let ownership = try controller.completePreparedEnable(plan)
            try writeJournal(.init(enabled: true, phase: .applied, ownership: ownership))
        } else if let journal = try readJournal() {
            try writeJournal(.init(enabled: false, phase: .prepared, ownership: journal.ownership))
            try controller.disable(ownership: journal.ownership)
            try ownershipStore.writeCapsLockJournalData(nil)
        }
    }

    func currentCapsLockEnabled() throws -> Bool {
        guard let journal = try readJournal() else { return false }
        return try controller.isApplied(journal.ownership)
    }

    private func readJournal() throws -> CapsJournal? {
        guard let data = ownershipStore.readCapsLockJournalData() else { return nil }
        return try decoder.decode(CapsJournal.self, from: data)
    }

    private func writeJournal(_ journal: CapsJournal) throws {
        try ownershipStore.writeCapsLockJournalData(try encoder.encode(journal))
    }
}

final class InputFeaturesAdapter: TidyTapInputFeaturesApplying {
    private final class RuntimeSink: @unchecked Sendable { var handler: ((EventTapStatus) -> Void)? }
    private let controller: EventTapController
    private let runtimeSink: RuntimeSink
    private let stateLock = NSLock()
    private var isApplying = false
    private var activeRequestID: UUID?
    /// The engine's effective configuration correctly turns the feature off
    /// when permissions disappear. Keep the user's last selected size outside
    /// that effective state so pass-through and a fresh disabled application do
    /// not turn it back into the engine default.
    private var rememberedMouseWheelStepLines = TidyTapSettings.defaultMouseWheelStepLines
    var runtimeStatusHandler: ((UUID, TidyTapInputFeatureApplyResult?, TidyTapInputFeatureAdapterError?) -> Void)?

    init(
        permissionChecker: any InputPermissionChecking = CGInputPermissionChecker(),
        backend: any EventTapBackend = CGEventTapBackend(),
        sideButtons: SideButtonController = SideButtonController(
            applicationProvider: MacOSFocusedApplicationProvider(),
            synthesizer: CGNavigationSynthesizer()
        )
    ) {
        let sink = RuntimeSink()
        runtimeSink = sink
        controller = EventTapController(
            permissions: permissionChecker,
            backend: backend,
            sideButtons: sideButtons,
            statusObserver: { status in sink.handler?(status) }
        )
        sink.handler = { [weak self] status in self?.report(status) }
    }

    func apply(
        reverseMouseWheel: Bool,
        sideButtonNavigation: Bool,
        fixedMouseWheelStepEnabled: Bool,
        mouseWheelStepLines: Int,
        requestID: UUID
    ) throws -> TidyTapInputFeatureApplyResult {
        stateLock.lock()
        isApplying = true
        rememberedMouseWheelStepLines = mouseWheelStepLines
        stateLock.unlock()
        defer {
            stateLock.lock()
            isApplying = false
            activeRequestID = requestID
            stateLock.unlock()
        }
        let configuration = EventTapConfiguration(
            reverseMouseScroll: reverseMouseWheel,
            sideButtonNavigation: sideButtonNavigation,
            fixedMouseWheelStepEnabled: fixedMouseWheelStepEnabled,
            mouseWheelStepLines: mouseWheelStepLines
        )
        switch controller.start(configuration: configuration) {
        case .stopped, .drainingButtonPresses, .running:
            return .applied
        case .partiallyRunning(_, let unavailablePermissions):
            return .partiallyApplied(unavailablePermissions: Set(unavailablePermissions.map(Self.permission)))
        case .permissionDenied(let missing):
            return .partiallyApplied(unavailablePermissions: Set(missing.map(Self.permission)))
        case .failed:
            throw TidyTapInputFeatureAdapterError.eventTapFailed
        }
    }

    func forcePassThrough() throws {
        stateLock.lock()
        isApplying = true
        stateLock.unlock()
        controller.stop()
        stateLock.lock()
        isApplying = false
        stateLock.unlock()
    }

    func currentConfiguration() -> TidyTapInputFeatureConfiguration {
        let configuration = controller.currentConfiguration
        stateLock.lock()
        let rememberedMouseWheelStepLines = rememberedMouseWheelStepLines
        stateLock.unlock()
        return TidyTapInputFeatureConfiguration(
            reverseMouseWheel: configuration.reverseMouseScroll,
            sideButtonNavigation: configuration.sideButtonNavigation,
            fixedMouseWheelStepEnabled: configuration.fixedMouseWheelStepEnabled,
            mouseWheelStepLines: rememberedMouseWheelStepLines
        )
    }

    private static func permission(_ permission: InputPermission) -> TidyTapPermission {
        switch permission {
        case .accessibility: .accessibility
        case .inputMonitoring: .inputMonitoring
        }
    }

    private func report(_ status: EventTapStatus) {
        stateLock.lock()
        let shouldSuppress = isApplying
        let requestID = activeRequestID
        stateLock.unlock()
        guard !shouldSuppress, let requestID else { return }

        switch status {
        case .running, .stopped, .drainingButtonPresses:
            runtimeStatusHandler?(requestID, .applied, nil)
        case .partiallyRunning(_, let missing):
            runtimeStatusHandler?(requestID, .partiallyApplied(unavailablePermissions: Set(missing.map(Self.permission))), nil)
        case .permissionDenied(let missing):
            runtimeStatusHandler?(requestID, .partiallyApplied(unavailablePermissions: Set(missing.map(Self.permission))), nil)
        case .failed:
            runtimeStatusHandler?(requestID, nil, .eventTapFailed)
        }
    }
}
