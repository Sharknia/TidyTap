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

protocol TidyTapLoginService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: TidyTapLoginService {}

/// Launchd starts the same in-bundle executable used by manual launches.
final class LoginItemCoordinator: TidyTapLoginItemManaging {
    private let service: any TidyTapLoginService
    private let legacy: any TidyTapLoginService

    init(
        service: any TidyTapLoginService = SMAppService.agent(plistName: TidyTapProduct.agentPlistName),
        legacy: any TidyTapLoginService = SMAppService.loginItem(identifier: TidyTapProduct.helperBundleIdentifier)
    ) {
        self.service = service
        self.legacy = legacy
    }

    func setEnabled(_ enabled: Bool) throws {
        // Retire the independently registered 0.0.2 login app during upgrade.
        if legacy.status == .enabled || legacy.status == .requiresApproval {
            try legacy.unregister()
        }
        if enabled {
            guard service.status != .enabled else { return }
            try service.register()
        } else {
            // A fresh install may not yet be known to ServiceManagement.
            // There is nothing to unregister in that state; attempting it
            // fails and used to block every unrelated feature toggle.
            guard service.status == .enabled || service.status == .requiresApproval else { return }
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
