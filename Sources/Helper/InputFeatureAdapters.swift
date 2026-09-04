import TidyTapInputEngine
import Foundation

/// Error values are deliberately stable and small: they cross the helper/UI
/// boundary only through `TidyTapApplyStatus.errorCode`, never as raw system
/// errors or command output.
enum TidyTapInputFeatureAdapterError: Error {
    case permissionDenied(Set<TidyTapPermission>)
    case eventTapFailed
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
        let ownership = try readOwnership()
        if capsLockEnabled {
            let updatedOwnership = try controller.enable(existingOwnership: ownership)
            try ownershipStore.writeCapsLockOwnershipData(try encoder.encode(updatedOwnership))
        } else if let ownership {
            try controller.disable(ownership: ownership)
            try ownershipStore.writeCapsLockOwnershipData(nil)
        }
    }

    private func readOwnership() throws -> CapsLockFeatureOwnership? {
        guard let data = ownershipStore.readCapsLockOwnershipData() else { return nil }
        return try decoder.decode(CapsLockFeatureOwnership.self, from: data)
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
