import TidyTapInputEngine
import Foundation

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
        requestID: UUID
    ) throws -> TidyTapInputFeatureApplyResult {
        stateLock.lock()
        isApplying = true
        stateLock.unlock()
        defer {
            stateLock.lock()
            isApplying = false
            activeRequestID = requestID
            stateLock.unlock()
        }
        let configuration = EventTapConfiguration(
            reverseMouseScroll: reverseMouseWheel,
            sideButtonNavigation: sideButtonNavigation
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
        return TidyTapInputFeatureConfiguration(
            reverseMouseWheel: configuration.reverseMouseScroll,
            sideButtonNavigation: configuration.sideButtonNavigation
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
