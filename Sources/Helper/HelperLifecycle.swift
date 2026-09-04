import Foundation

/// Listens only for a request signal; the full snapshot is always re-read from
/// the shared domain. This makes missed notifications harmless at next launch.
final class HelperLifecycle: NSObject {
    private let coordinator: ApplyCoordinator
    private var isObservingSettings = false

    init(coordinator: ApplyCoordinator) {
        self.coordinator = coordinator
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
        isObservingSettings = true
        _ = coordinator.applyLatestSettings()
    }

    func stop() {
        if isObservingSettings {
            DistributedNotificationCenter.default().removeObserver(self)
            isObservingSettings = false
        }
    }

    deinit {
        stop()
    }

    @objc private func settingsDidChange(_ notification: Notification) {
        _ = coordinator.applyLatestSettings()
    }
}
