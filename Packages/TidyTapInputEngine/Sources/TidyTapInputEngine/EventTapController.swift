import Foundation

public enum InputPermission: String, Hashable, Sendable {
    case accessibility
    case inputMonitoring
}

public protocol InputPermissionChecking: Sendable {
    var accessibilityAllowed: Bool { get }
    var inputMonitoringAllowed: Bool { get }
}

public struct EventTapConfiguration: Equatable, Sendable {
    public let reverseMouseScroll: Bool
    public let sideButtonNavigation: Bool

    public init(reverseMouseScroll: Bool, sideButtonNavigation: Bool) {
        self.reverseMouseScroll = reverseMouseScroll
        self.sideButtonNavigation = sideButtonNavigation
    }

    public var isEnabled: Bool { reverseMouseScroll || sideButtonNavigation }

    public var requiredPermissions: Set<InputPermission> {
        var result: Set<InputPermission> = []
        if reverseMouseScroll {
            result.formUnion([.accessibility, .inputMonitoring])
        }
        if sideButtonNavigation {
            result.insert(.accessibility)
        }
        return result
    }
}

public enum EventTapDisableReason: Equatable, Sendable {
    case timeout
    case userInput
}

public enum EventTapInput: Equatable, Sendable {
    case gesture(timestampNanoseconds: UInt64)
    case scroll(ScrollObservation)
    case buttonDown(Int64)
    case buttonUp(Int64)
    case disabled(EventTapDisableReason)
}

public enum EventTapOutput: Equatable, Sendable {
    case passThrough
    case consume
    case replaceScrollDeltas(ScrollDeltaFields)
}

public typealias EventTapHandler = @Sendable (EventTapInput) -> EventTapOutput

public protocol EventTapBackend: AnyObject, Sendable {
    func install(
        configuration: EventTapConfiguration,
        captureSideButtons: Bool,
        handler: @escaping EventTapHandler
    ) throws
    func enable() throws
    func uninstall()
}

public enum EventTapStatus: Equatable, Sendable {
    case stopped
    case drainingButtonPresses
    case running(EventTapConfiguration)
    case partiallyRunning(
        EventTapConfiguration,
        unavailablePermissions: Set<InputPermission>
    )
    case permissionDenied(Set<InputPermission>)
    case failed(InputEngineError)
}

public final class EventTapController: @unchecked Sendable {
    private let permissions: any InputPermissionChecking
    private let backend: any EventTapBackend
    private let sideButtons: SideButtonController
    private let lock = NSLock()
    private var scroll = ScrollController()
    private var configuration = EventTapConfiguration(
        reverseMouseScroll: false,
        sideButtonNavigation: false
    )
    private var storedStatus: EventTapStatus = .stopped

    public init(
        permissions: any InputPermissionChecking,
        backend: any EventTapBackend,
        sideButtons: SideButtonController
    ) {
        self.permissions = permissions
        self.backend = backend
        self.sideButtons = sideButtons
    }

    public var status: EventTapStatus {
        lock.lock()
        defer { lock.unlock() }
        return storedStatus
    }

    @discardableResult
    public func start(configuration: EventTapConfiguration) -> EventTapStatus {
        backend.uninstall()
        lock.lock()
        self.configuration = configuration
        scroll = ScrollController()
        lock.unlock()

        let drainingSideButtons = sideButtons.hasActivePresses
        guard configuration.isEnabled || drainingSideButtons else {
            return updateStatus(.stopped)
        }
        let missing = missingPermissions(
            for: configuration,
            includeSideButtonDrain: drainingSideButtons
        )
        guard missing.isEmpty else {
            if missing == [.inputMonitoring], configuration.sideButtonNavigation {
                do {
                    try installBackend(
                        configuration: Self.sideButtonOnlyConfiguration,
                        captureSideButtons: true
                    )
                    return updateStatus(.partiallyRunning(
                        configuration,
                        unavailablePermissions: missing
                    ))
                } catch {
                    sideButtons.reset()
                    return updateStatus(.failed(.eventTapCreationFailed))
                }
            }
            if !configuration.isEnabled {
                sideButtons.reset()
                return updateStatus(.stopped)
            }
            return updateStatus(.permissionDenied(missing))
        }

        do {
            try installBackend(
                configuration: configuration,
                captureSideButtons: configuration.sideButtonNavigation || drainingSideButtons
            )
            return updateStatus(
                configuration.isEnabled ? .running(configuration) : .drainingButtonPresses
            )
        } catch let error as InputEngineError {
            return updateStatus(.failed(error))
        } catch {
            return updateStatus(.failed(.eventTapCreationFailed))
        }
    }

    public func stop() {
        backend.uninstall()
        sideButtons.reset()
        _ = updateStatus(.stopped)
    }

    private func handle(_ input: EventTapInput) -> EventTapOutput {
        switch input {
        case .gesture(let timestamp):
            lock.lock()
            let enabled = configuration.reverseMouseScroll
            lock.unlock()
            guard enabled else { return .passThrough }
            let missing = missingPermissions(
                required: [.accessibility, .inputMonitoring]
            )
            guard missing.isEmpty else {
                updatePermissionLossStatus(missing)
                return .passThrough
            }
            lock.lock()
            if configuration.reverseMouseScroll {
                scroll.observeGesture(at: timestamp)
            }
            lock.unlock()
            return .passThrough

        case .scroll(let observation):
            lock.lock()
            guard configuration.reverseMouseScroll else {
                lock.unlock()
                return .passThrough
            }
            let currentConfiguration = configuration
            lock.unlock()
            let missing = missingPermissions(
                required: [.accessibility, .inputMonitoring]
            )
            guard missing.isEmpty else {
                updatePermissionLossStatus(missing)
                return .passThrough
            }
            lock.lock()
            guard configuration == currentConfiguration, configuration.reverseMouseScroll else {
                lock.unlock()
                return .passThrough
            }
            let result = scroll.process(observation)
            lock.unlock()
            return result.didInvert ? .replaceScrollDeltas(result.outputDeltas) : .passThrough

        case .buttonDown(let button):
            lock.lock()
            let enabled = configuration.sideButtonNavigation
            lock.unlock()
            guard enabled || sideButtons.hasActivePresses else { return .passThrough }
            let missing = missingPermissions(required: [.accessibility])
            guard missing.isEmpty else {
                sideButtons.reset()
                handleButtonPermissionLoss(missing)
                return .passThrough
            }
            let disposition = sideButtons.handleButtonDown(
                button,
                navigationEnabled: enabled
            )
            return disposition == .consume ? .consume : .passThrough

        case .buttonUp(let button):
            lock.lock()
            let enabled = configuration.sideButtonNavigation
            lock.unlock()
            guard enabled || sideButtons.hasActivePresses else { return .passThrough }
            let missing = missingPermissions(required: [.accessibility])
            guard missing.isEmpty else {
                sideButtons.reset()
                handleButtonPermissionLoss(missing)
                return .passThrough
            }
            let disposition = sideButtons.handleButtonUp(button)
            finishDrainingIfNeeded()
            return disposition == .consume ? .consume : .passThrough

        case .disabled:
            return recoverDisabledTap()
        }
    }

    private func recoverDisabledTap() -> EventTapOutput {
        lock.lock()
        let currentConfiguration = configuration
        lock.unlock()
        let missing = missingPermissions(
            for: currentConfiguration,
            includeSideButtonDrain: sideButtons.hasActivePresses
        )
        guard missing.isEmpty else {
            if
                missing == [.inputMonitoring],
                currentConfiguration.sideButtonNavigation
            {
                do {
                    try installBackend(
                        configuration: Self.sideButtonOnlyConfiguration,
                        captureSideButtons: true
                    )
                    _ = updateStatus(.partiallyRunning(
                        currentConfiguration,
                        unavailablePermissions: missing
                    ))
                } catch {
                    sideButtons.reset()
                    _ = updateStatus(.failed(.eventTapRecoveryFailed))
                }
                return .passThrough
            }
            if missing.contains(.accessibility) {
                sideButtons.reset()
            }
            if currentConfiguration.isEnabled {
                _ = updateStatus(.permissionDenied(missing))
            } else {
                backend.uninstall()
                _ = updateStatus(.stopped)
            }
            return .passThrough
        }
        do {
            try backend.enable()
            _ = updateStatus(
                currentConfiguration.isEnabled ? .running(currentConfiguration) : .drainingButtonPresses
            )
        } catch {
            sideButtons.reset()
            _ = updateStatus(.failed(.eventTapRecoveryFailed))
        }
        return .passThrough
    }

    private func missingPermissions(
        for configuration: EventTapConfiguration,
        includeSideButtonDrain: Bool = false
    ) -> Set<InputPermission> {
        var required = configuration.requiredPermissions
        if includeSideButtonDrain { required.insert(.accessibility) }
        return missingPermissions(required: required)
    }

    private func missingPermissions(
        required: Set<InputPermission>
    ) -> Set<InputPermission> {
        required.filter { permission in
            switch permission {
            case .accessibility: !permissions.accessibilityAllowed
            case .inputMonitoring: !permissions.inputMonitoringAllowed
            }
        }
    }

    private func finishDrainingIfNeeded() {
        guard !sideButtons.hasActivePresses else { return }
        lock.lock()
        let currentConfiguration = configuration
        lock.unlock()
        guard !currentConfiguration.sideButtonNavigation else { return }
        if currentConfiguration.isEnabled {
            _ = updateStatus(.running(currentConfiguration))
        } else {
            backend.uninstall()
            _ = updateStatus(.stopped)
        }
    }

    private func handleButtonPermissionLoss(_ missing: Set<InputPermission>) {
        lock.lock()
        let currentConfiguration = configuration
        lock.unlock()
        if currentConfiguration.isEnabled {
            _ = updateStatus(.permissionDenied(missing))
        } else {
            backend.uninstall()
            _ = updateStatus(.stopped)
        }
    }

    private func updatePermissionLossStatus(_ missing: Set<InputPermission>) {
        lock.lock()
        let currentConfiguration = configuration
        lock.unlock()
        if missing == [.inputMonitoring], currentConfiguration.sideButtonNavigation {
            _ = updateStatus(.partiallyRunning(
                currentConfiguration,
                unavailablePermissions: missing
            ))
        } else {
            _ = updateStatus(.permissionDenied(missing))
        }
    }

    private func installBackend(
        configuration: EventTapConfiguration,
        captureSideButtons: Bool
    ) throws {
        try backend.install(
            configuration: configuration,
            captureSideButtons: captureSideButtons
        ) { [weak self] input in
            self?.handle(input) ?? .passThrough
        }
    }

    private static let sideButtonOnlyConfiguration = EventTapConfiguration(
        reverseMouseScroll: false,
        sideButtonNavigation: true
    )

    @discardableResult
    private func updateStatus(_ status: EventTapStatus) -> EventTapStatus {
        lock.lock()
        storedStatus = status
        lock.unlock()
        return status
    }
}
