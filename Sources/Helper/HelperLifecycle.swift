import Foundation

/// Listens only for a request signal; the full snapshot is always re-read from
/// the shared domain. This makes missed notifications harmless at next launch.
@MainActor
final class HelperLifecycle: NSObject {
    private let coordinator: ApplyCoordinator
    private let permissionCoordinator: HelperPermissionCoordinator
    private let afterApply: (TidyTapApplyStatus) -> Void
    private var isObservingSettings = false

    init(
        coordinator: ApplyCoordinator,
        permissionCoordinator: HelperPermissionCoordinator,
        afterApply: @escaping (TidyTapApplyStatus) -> Void = { _ in }
    ) {
        self.coordinator = coordinator
        self.permissionCoordinator = permissionCoordinator
        self.afterApply = afterApply
    }

    func start() {
        guard !isObservingSettings else { return }
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(settingsDidChange(_:)),
            name: TidyTapIPC.settingsDidChange,
            object: TidyTapProduct.appBundleIdentifier,
            suspensionBehavior: .deliverImmediately
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(permissionRequestDidArrive(_:)),
            name: TidyTapIPC.permissionRequest,
            object: TidyTapProduct.appBundleIdentifier,
            suspensionBehavior: .deliverImmediately
        )
        isObservingSettings = true
        let permissionResult = permissionCoordinator.handleLatestRequest()
        let startupResult = coordinator.applyLatestSettings()
        let preserved = permissionCoordinator.restoreOutstandingPermissionFailure(
            after: permissionResult,
            startupApply: startupResult
        )
        afterApply(preserved ?? startupResult)
    }

    func stop() {
        if isObservingSettings {
            DistributedNotificationCenter.default().removeObserver(self)
            isObservingSettings = false
        }
    }

    @objc private func settingsDidChange(_ notification: Notification) {
        afterApply(coordinator.applyLatestSettings())
    }

    @objc private func permissionRequestDidArrive(_ notification: Notification) {
        _ = permissionCoordinator.handleLatestRequest()
    }
}
