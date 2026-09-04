import TidyTapInputEngine
import Foundation

/// Error values are deliberately stable and small: they cross the helper/UI
/// boundary only through `TidyTapApplyStatus.errorCode`, never as raw system
/// errors or command output.
enum TidyTapInputFeatureAdapterError: Error {
    case permissionDenied(Set<TidyTapPermission>)
    case eventTapFailed
}

private enum CapsJournalPhase: String, Codable { case prepared, applied }
private struct CapsJournal: Codable {
    let enabled: Bool
    let phase: CapsJournalPhase
    let ownership: CapsLockFeatureOwnership
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
            if let journal = try readJournal(), journal.enabled {
                if journal.phase == .applied { return }
                // A crash after mutation is finalized on restart; a pre-mutation
                // journal is retried safely by the engine's ownership checks.
                let ownership = try controller.enable(existingOwnership: nil)
                try writeJournal(.init(enabled: true, phase: .applied, ownership: ownership))
                return
            }
            let ownership = try controller.enable(existingOwnership: nil)
            try writeJournal(.init(enabled: true, phase: .applied, ownership: ownership))
        } else if let journal = try readJournal() {
            try writeJournal(.init(enabled: false, phase: .prepared, ownership: journal.ownership))
            try controller.disable(ownership: journal.ownership)
            try ownershipStore.writeCapsLockJournalData(nil)
        }
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
    private let controller: EventTapController

    init(
        permissionChecker: any InputPermissionChecking = CGInputPermissionChecker(),
        backend: any EventTapBackend = CGEventTapBackend(),
        sideButtons: SideButtonController = SideButtonController(
            applicationProvider: MacOSFocusedApplicationProvider(),
            synthesizer: CGNavigationSynthesizer()
        )
    ) {
        controller = EventTapController(
            permissions: permissionChecker,
            backend: backend,
            sideButtons: sideButtons
        )
    }

    func apply(
        reverseMouseWheel: Bool,
        sideButtonNavigation: Bool
    ) throws -> TidyTapInputFeatureApplyResult {
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
            throw TidyTapInputFeatureAdapterError.permissionDenied(Set(missing.map(Self.permission)))
        case .failed:
            throw TidyTapInputFeatureAdapterError.eventTapFailed
        }
    }

    func forcePassThrough() throws {
        controller.stop()
    }

    private static func permission(_ permission: InputPermission) -> TidyTapPermission {
        switch permission {
        case .accessibility: .accessibility
        case .inputMonitoring: .inputMonitoring
        }
    }
}
