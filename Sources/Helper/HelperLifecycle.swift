import Foundation
import AppKit
import IOKit
import os

/// Listens only for a request signal; the full snapshot is always re-read from
/// the shared domain. This makes missed notifications harmless at next launch.
@MainActor
final class HelperLifecycle: NSObject {
    private let coordinator: ApplyCoordinator
    private let permissionCoordinator: HelperPermissionCoordinator
    private let afterApply: (TidyTapApplyStatus) -> Void
    private var isObservingSettings = false
    private var deviceMonitor: KeyboardDeviceMonitor?
    private var pendingDeviceRefresh: DispatchWorkItem?

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
        pendingDeviceRefresh?.cancel()
        pendingDeviceRefresh = nil
        deviceMonitor?.stop()
        deviceMonitor = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        if isObservingSettings {
            DistributedNotificationCenter.default().removeObserver(self)
            isObservingSettings = false
        }
    }

    @discardableResult
    func monitorConnectedDevices() -> Bool {
        guard deviceMonitor == nil else { return true }
        let monitor = KeyboardDeviceMonitor { [weak self] in self?.scheduleDeviceRefresh() }
        guard monitor.start() else {
            Logger(subsystem: TidyTapProduct.appBundleIdentifier, category: "devices")
                .error("Could not register input device notifications")
            return false
        }
        deviceMonitor = monitor
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake(_:)), name: NSWorkspace.didWakeNotification, object: nil
        )
        Logger(subsystem: TidyTapProduct.appBundleIdentifier, category: "devices")
            .notice("Input device notifications registered")
        return true
    }

    @objc private func systemDidWake(_ notification: Notification) { scheduleDeviceRefresh() }

    private func scheduleDeviceRefresh() {
        pendingDeviceRefresh?.cancel()
        let refresh = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.refreshConnectedDevices() }
        }
        pendingDeviceRefresh = refresh
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: refresh)
    }

    func refreshConnectedDevices() {
        guard isObservingSettings else { return }
        Logger(subsystem: TidyTapProduct.appBundleIdentifier, category: "devices")
            .notice("Reapplying input settings after device change or wake")
        afterApply(coordinator.applyLatestSettings())
    }

    @objc private func settingsDidChange(_ notification: Notification) {
        afterApply(coordinator.applyLatestSettings())
    }

    @objc private func permissionRequestDidArrive(_ notification: Notification) {
        _ = permissionCoordinator.handleLatestRequest()
    }
}

/// Watches device arrival/removal without opening devices or reading input.
@MainActor
private final class KeyboardDeviceMonitor {
    private let onChange: () -> Void
    private var port: IONotificationPortRef?
    private var iterators: [io_iterator_t] = []

    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    func start() -> Bool {
        if port != nil { return true }
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return false }
        self.port = port
        IONotificationPortSetDispatchQueue(port, .main)
        for kind in [kIOFirstMatchNotification, kIOTerminatedNotification] {
            var iterator: io_iterator_t = 0
            let result = IOServiceAddMatchingNotification(
                port, kind, IOServiceMatching("IOHIDEventService"),
                { context, iterator in
                    guard let context else { return }
                    MainActor.assumeIsolated {
                        let monitor = Unmanaged<KeyboardDeviceMonitor>.fromOpaque(context).takeUnretainedValue()
                        monitor.drain(iterator)
                        monitor.onChange()
                    }
                },
                Unmanaged.passUnretained(self).toOpaque(), &iterator
            )
            guard result == KERN_SUCCESS else { stop(); return false }
            iterators.append(iterator)
            drain(iterator)
        }
        return true
    }

    private func drain(_ iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 { IOObjectRelease(service) }
    }

    func stop() {
        if let port { IONotificationPortSetDispatchQueue(port, nil) }
        for iterator in iterators { IOObjectRelease(iterator) }
        iterators.removeAll()
        if let port { IONotificationPortDestroy(port) }
        port = nil
    }
}
