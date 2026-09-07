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
    public let fixedMouseWheelStepEnabled: Bool
    public let mouseWheelStepLines: Int

    public init(
        reverseMouseScroll: Bool,
        sideButtonNavigation: Bool,
        fixedMouseWheelStepEnabled: Bool = false,
        mouseWheelStepLines: Int = 3
    ) {
        self.reverseMouseScroll = reverseMouseScroll
        self.sideButtonNavigation = sideButtonNavigation
        self.fixedMouseWheelStepEnabled = fixedMouseWheelStepEnabled
        self.mouseWheelStepLines = min(max(mouseWheelStepLines, 1), 10)
    }

    public var needsScrollProcessing: Bool {
        reverseMouseScroll || fixedMouseWheelStepEnabled
    }

    public var isEnabled: Bool { needsScrollProcessing || sideButtonNavigation }

    public var requiredPermissions: Set<InputPermission> {
        var result: Set<InputPermission> = []
        if needsScrollProcessing {
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
    case setVerticalScrollStep(lines: Int64)
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
    private let statusObserver: (@Sendable (EventTapStatus) -> Void)?
    private let lock = NSLock()
    private var scroll = ScrollController()
    private var configuration = EventTapConfiguration(
        reverseMouseScroll: false,
        sideButtonNavigation: false
    )
    private var storedStatus: EventTapStatus = .stopped
    private var generation: UInt64 = 0

    public init(
        permissions: any InputPermissionChecking,
        backend: any EventTapBackend,
        sideButtons: SideButtonController,
        statusObserver: (@Sendable (EventTapStatus) -> Void)? = nil
    ) {
        self.permissions = permissions
        self.backend = backend
        self.sideButtons = sideButtons
        self.statusObserver = statusObserver
    }

    public var status: EventTapStatus {
        lock.lock()
        defer { lock.unlock() }
        return storedStatus
    }

    public var currentConfiguration: EventTapConfiguration {
        lock.lock()
        defer { lock.unlock() }
        return configuration
    }

    @discardableResult
    public func start(configuration: EventTapConfiguration) -> EventTapStatus {
        lock.lock()
        generation &+= 1
        let generation = generation
        self.configuration = configuration
        scroll = ScrollController()
        lock.unlock()
        backend.uninstall()

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
                        captureSideButtons: true,
                        generation: generation
                    )
                    setEffectiveConfiguration(
                        Self.effectiveConfiguration(for: configuration, missing: missing)
                    )
                    return updateStatus(.partiallyRunning(
                        configuration,
                        unavailablePermissions: missing
                    ))
                } catch {
                    sideButtons.reset()
                    setEffectiveConfiguration(Self.disabledConfiguration)
                    return updateStatus(.failed(.eventTapCreationFailed))
                }
            }
            if !configuration.isEnabled {
                sideButtons.reset()
                return updateStatus(.stopped)
            }
            setEffectiveConfiguration(
                Self.effectiveConfiguration(for: configuration, missing: missing)
            )
            return updateStatus(.permissionDenied(missing))
        }

        do {
            try installBackend(
                configuration: configuration,
                captureSideButtons: configuration.sideButtonNavigation || drainingSideButtons,
                generation: generation
            )
            return updateStatus(
                configuration.isEnabled ? .running(configuration) : .drainingButtonPresses
            )
        } catch let error as InputEngineError {
            setEffectiveConfiguration(Self.disabledConfiguration)
            return updateStatus(.failed(error))
        } catch {
            setEffectiveConfiguration(Self.disabledConfiguration)
            return updateStatus(.failed(.eventTapCreationFailed))
        }
    }

    public func stop() {
        lock.lock()
        generation &+= 1
        configuration = EventTapConfiguration(reverseMouseScroll: false, sideButtonNavigation: false)
        scroll = ScrollController()
        lock.unlock()
        backend.uninstall()
        sideButtons.reset()
        _ = updateStatus(.stopped)
    }

    private func handle(_ input: EventTapInput, generation: UInt64) -> EventTapOutput {
        lock.lock()
        let isCurrentGeneration = self.generation == generation
        lock.unlock()
        guard isCurrentGeneration else { return .passThrough }
        switch input {
        case .gesture(let timestamp):
            lock.lock()
            let enabled = configuration.needsScrollProcessing
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
            if configuration.needsScrollProcessing {
                scroll.observeGesture(at: timestamp)
            }
            lock.unlock()
            return .passThrough

        case .scroll(let observation):
            lock.lock()
            guard configuration.needsScrollProcessing else {
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
            guard configuration == currentConfiguration, configuration.needsScrollProcessing else {
                lock.unlock()
                return .passThrough
            }
            let result = scroll.process(
                observation,
                reverseMouseScroll: configuration.reverseMouseScroll,
                fixedMouseWheelStepEnabled: configuration.fixedMouseWheelStepEnabled,
                mouseWheelStepLines: configuration.mouseWheelStepLines
            )
            lock.unlock()
            switch result.mutation {
            case .passThrough:
                return .passThrough
            case .reverseVerticalDeltas(let deltas):
                return .replaceScrollDeltas(deltas)
            case .setVerticalScrollStep(let lines):
                return .setVerticalScrollStep(lines: lines)
            }

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
                        captureSideButtons: true,
                        generation: currentGeneration()
                    )
                    setEffectiveConfiguration(
                        Self.effectiveConfiguration(for: currentConfiguration, missing: missing)
                    )
                    _ = updateStatus(.partiallyRunning(
                        currentConfiguration,
                        unavailablePermissions: missing
                    ))
                } catch {
                    sideButtons.reset()
                    setEffectiveConfiguration(Self.disabledConfiguration)
                    _ = updateStatus(.failed(.eventTapRecoveryFailed))
                }
                return .passThrough
            }
            if missing.contains(.accessibility) {
                sideButtons.reset()
            }
            if currentConfiguration.isEnabled {
                setEffectiveConfiguration(
                    Self.effectiveConfiguration(for: currentConfiguration, missing: missing)
                )
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
            setEffectiveConfiguration(Self.disabledConfiguration)
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
            setEffectiveConfiguration(
                Self.effectiveConfiguration(for: currentConfiguration, missing: missing)
            )
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
        setEffectiveConfiguration(
            Self.effectiveConfiguration(for: currentConfiguration, missing: missing)
        )
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
        captureSideButtons: Bool,
        generation: UInt64
    ) throws {
        try backend.install(
            configuration: configuration,
            captureSideButtons: captureSideButtons
        ) { [weak self] input in
            self?.handle(input, generation: generation) ?? .passThrough
        }
    }

    private func currentGeneration() -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    private func setEffectiveConfiguration(_ configuration: EventTapConfiguration) {
        lock.lock()
        self.configuration = configuration
        if !configuration.needsScrollProcessing { scroll = ScrollController() }
        lock.unlock()
    }

    private static func effectiveConfiguration(
        for requested: EventTapConfiguration,
        missing: Set<InputPermission>
    ) -> EventTapConfiguration {
        EventTapConfiguration(
            reverseMouseScroll: requested.reverseMouseScroll && missing.isDisjoint(with: [.accessibility, .inputMonitoring]),
            sideButtonNavigation: requested.sideButtonNavigation && !missing.contains(.accessibility),
            fixedMouseWheelStepEnabled: requested.fixedMouseWheelStepEnabled && missing.isDisjoint(with: [.accessibility, .inputMonitoring]),
            mouseWheelStepLines: requested.mouseWheelStepLines
        )
    }

    private static let sideButtonOnlyConfiguration = EventTapConfiguration(
        reverseMouseScroll: false,
        sideButtonNavigation: true
    )

    private static let disabledConfiguration = EventTapConfiguration(
        reverseMouseScroll: false,
        sideButtonNavigation: false
    )

    @discardableResult
    private func updateStatus(_ status: EventTapStatus) -> EventTapStatus {
        lock.lock()
        storedStatus = status
        lock.unlock()
        statusObserver?(status)
        return status
    }
}
