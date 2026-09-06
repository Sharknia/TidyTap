import Foundation
import ServiceManagement

enum TidyTapLoginItemStatus: Equatable {
    case enabled
    case disabled
    case requiresApproval
    case unavailable
}

protocol TidyTapLoginItemManaging: AnyObject {
    func setEnabled(_ enabled: Bool) throws
    func status() -> TidyTapLoginItemStatus
}

/// Launchd starts the same in-bundle executable used by manual launches.
final class LoginItemCoordinator: TidyTapLoginItemManaging {
    private let service: SMAppService

    init(service: SMAppService = .agent(plistName: TidyTapProduct.agentPlistName)) {
        self.service = service
    }

    func setEnabled(_ enabled: Bool) throws {
        // Retire the independently registered 0.0.2 login app during upgrade.
        let legacy = SMAppService.loginItem(identifier: TidyTapProduct.helperBundleIdentifier)
        if legacy.status == .enabled || legacy.status == .requiresApproval {
            try legacy.unregister()
        }
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }

    func status() -> TidyTapLoginItemStatus {
        switch service.status {
        case .enabled:
            .enabled
        case .notRegistered:
            .disabled
        case .requiresApproval:
            .requiresApproval
        case .notFound:
            .unavailable
        @unknown default:
            .unavailable
        }
    }
}
