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
    func install(configuration: EventTapConfiguration, handler: @escaping EventTapHandler) throws
    func enable() throws
    func uninstall()
}

public enum EventTapStatus: Equatable, Sendable {
    case stopped
    case running(EventTapConfiguration)
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
        sideButtons.reset()
        lock.lock()
        self.configuration = configuration
        scroll = ScrollController()
        lock.unlock()

        guard configuration.isEnabled else {
            return updateStatus(.stopped)
        }
        let missing = missingPermissions(for: configuration)
        guard missing.isEmpty else {
            return updateStatus(.permissionDenied(missing))
        }

        do {
            try backend.install(configuration: configuration) { [weak self] input in
                self?.handle(input) ?? .passThrough
            }
            return updateStatus(.running(configuration))
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
            let result = scroll.process(observation)
            lock.unlock()
            return result.didInvert ? .replaceScrollDeltas(result.outputDeltas) : .passThrough

        case .buttonDown(let button):
            lock.lock()
            let enabled = configuration.sideButtonNavigation
            lock.unlock()
            guard enabled else { return .passThrough }
            return sideButtons.handleButtonDown(button) == .consume ? .consume : .passThrough

        case .buttonUp(let button):
            lock.lock()
            let enabled = configuration.sideButtonNavigation
            lock.unlock()
            guard enabled else { return .passThrough }
            return sideButtons.handleButtonUp(button) == .consume ? .consume : .passThrough

        case .disabled:
            return recoverDisabledTap()
        }
    }

    private func recoverDisabledTap() -> EventTapOutput {
        lock.lock()
        let currentConfiguration = configuration
        lock.unlock()
        let missing = missingPermissions(for: currentConfiguration)
        guard missing.isEmpty else {
            _ = updateStatus(.permissionDenied(missing))
            return .passThrough
        }
        do {
            try backend.enable()
            _ = updateStatus(.running(currentConfiguration))
        } catch {
            _ = updateStatus(.failed(.eventTapRecoveryFailed))
        }
        return .passThrough
    }

    private func missingPermissions(for configuration: EventTapConfiguration) -> Set<InputPermission> {
        configuration.requiredPermissions.filter { permission in
            switch permission {
            case .accessibility: !permissions.accessibilityAllowed
            case .inputMonitoring: !permissions.inputMonitoringAllowed
            }
        }
    }

    @discardableResult
    private func updateStatus(_ status: EventTapStatus) -> EventTapStatus {
        lock.lock()
        storedStatus = status
        lock.unlock()
        return status
    }
}
