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

/// Registers the embedded helper, never the main Dock app, as the login item.
final class LoginItemCoordinator: TidyTapLoginItemManaging {
    private let service: SMAppService

    init(service: SMAppService = .loginItem(identifier: TidyTapProduct.helperBundleIdentifier)) {
        self.service = service
    }

    func setEnabled(_ enabled: Bool) throws {
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
        @unknown default:
            .unavailable
        }
    }
}
