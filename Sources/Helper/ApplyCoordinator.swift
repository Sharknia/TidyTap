import AppKit
import TidyTapInputEngine

/// Feature-specific implementations live in later stages. These narrow
/// interfaces keep the lifecycle transaction independent of CGEvent/HID APIs.
protocol TidyTapCapsFeatureApplying: AnyObject {
    func apply(capsLockEnabled: Bool) throws
    func currentCapsLockEnabled() throws -> Bool
}

struct TidyTapInputFeatureConfiguration: Equatable {
    var reverseMouseWheel: Bool
    var sideButtonNavigation: Bool

    static let disabled = Self(reverseMouseWheel: false, sideButtonNavigation: false)
}

protocol TidyTapInputFeaturesApplying: AnyObject {
    func apply(
        reverseMouseWheel: Bool,
        sideButtonNavigation: Bool,
        requestID: UUID
    ) throws -> TidyTapInputFeatureApplyResult
    func forcePassThrough() throws
    func currentConfiguration() -> TidyTapInputFeatureConfiguration
}

enum TidyTapInputFeatureApplyResult: Equatable {
    case applied
    case partiallyApplied(unavailablePermissions: Set<TidyTapPermission>)
}

@MainActor
protocol TidyTapMenuBarApplying: AnyObject {
    func applyMenuBar(visible: Bool) throws
    var isMenuBarVisible: Bool { get }
}

protocol TidyTapTerminating: AnyObject {
    func terminate()
}

/// Runs the whole settings snapshot as one serial transaction. On any failure,
/// it reapplies the last known-good snapshot in reverse component order.
@MainActor
final class ApplyCoordinator {
    private let preferences: TidyTapPreferencesStoring
    private let capsFeature: TidyTapCapsFeatureApplying
    private let inputFeatures: TidyTapInputFeaturesApplying
    private let menuBar: TidyTapMenuBarApplying
    private let terminator: TidyTapTerminating
    private var activeRequest: TidyTapSettingsRequest?

    init(
        preferences: TidyTapPreferencesStoring,
        capsFeature: TidyTapCapsFeatureApplying,
        inputFeatures: TidyTapInputFeaturesApplying,
        menuBar: TidyTapMenuBarApplying,
        terminator: TidyTapTerminating
    ) {
        self.preferences = preferences
        self.capsFeature = capsFeature
        self.inputFeatures = inputFeatures
        self.menuBar = menuBar
        self.terminator = terminator
    }

    @discardableResult
    func applyLatestSettings() -> TidyTapApplyStatus {
        apply(preferences.readRequest())
    }

    /// Runtime permission revocation/recovery happens outside a settings write;
    /// persist a correlated result so a running Dock app updates immediately.
    func reportRuntimeInput(
        requestID: UUID,
        _ result: TidyTapInputFeatureApplyResult?,
        error: TidyTapInputFeatureAdapterError?
    ) {
        guard let activeRequest, activeRequest.applyRequestID == requestID else { return }
        let inputConfiguration = inputFeatures.currentConfiguration()
        var runtimeResult = result
        var runtimeError = error
        // Permission loss changes the controller's effective configuration in
        // the event callback without mutating the live backend. This method is
        // dispatched to the main actor after the callback returns, so it is the
        // safe point to uninstall/reinstall the tap to match that configuration.
        if result != nil {
            do {
                _ = try inputFeatures.apply(
                    reverseMouseWheel: inputConfiguration.reverseMouseWheel,
                    sideButtonNavigation: inputConfiguration.sideButtonNavigation,
                    requestID: requestID
                )
            } catch let adapterError as TidyTapInputFeatureAdapterError {
                runtimeResult = nil
                runtimeError = adapterError
            } catch {
                runtimeResult = nil
                runtimeError = .eventTapFailed
            }
        }
        let normalizedInputConfiguration = inputFeatures.currentConfiguration()
        var effective = activeRequest.settings
        effective.reverseMouseWheelVertically = normalizedInputConfiguration.reverseMouseWheel
        effective.sideButtonNavigation = normalizedInputConfiguration.sideButtonNavigation
        let status: TidyTapApplyStatus
        if let runtimeResult {
            switch runtimeResult {
            case .applied:
                status = .applied(requestID, effectiveSettings: effective)
            case .partiallyApplied(let permissions):
                status = TidyTapApplyStatus(
                    applyRequestID: requestID,
                    outcome: .partiallyApplied,
                    failedComponent: .eventTap,
                    errorCode: permissionCode(prefix: "eventTap.permissionPartial", permissions: permissions),
                    effectiveSettings: effective
                )
            }
        } else {
            status = failure(
                requestID,
                component: .eventTap,
                error: runtimeError ?? .eventTapFailed,
                effectiveSettings: effective
            )
        }
        let latest = preferences.readRequest()
        if latest.applyRequestID == requestID, latest.settings != effective {
            try? preferences.write(settings: effective, applyRequestID: requestID)
        }
        self.activeRequest = TidyTapSettingsRequest(settings: effective, applyRequestID: requestID)
        report(status)
        if !effective.requiresHelper { terminator.terminate() }
    }

    @discardableResult
    func apply(_ request: TidyTapSettingsRequest) -> TidyTapApplyStatus {
        let previousState: ControllerState
        do {
            previousState = try captureControllerState()
        } catch {
            let result = failure(
                request.applyRequestID,
                component: .lifecycle,
                error: error,
                effectiveSettings: request.settings
            )
            report(result)
            return result
        }
        let attempt = apply(request.settings, requestID: request.applyRequestID)
        var result = attempt.status
        if result.outcome == .applied || result.outcome == .partiallyApplied {
            let effective = effectiveSettings(request.settings)
            result = result.withEffectiveSettings(effective)
            activeRequest = TidyTapSettingsRequest(settings: effective, applyRequestID: request.applyRequestID)
            if effective != request.settings {
                try? preferences.write(settings: effective, applyRequestID: request.applyRequestID)
            }
        } else {
            let rollbackFailures = restore(previousState, touchedComponents: attempt.touchedComponents, requestID: request.applyRequestID)
            let restored = settings(request.settings, applying: previousState)
            if !rollbackFailures.isEmpty {
                let failureCodes = rollbackFailures.map(\.rawValue).joined(separator: ".")
                let recoveryResult = TidyTapApplyStatus(
                    applyRequestID: request.applyRequestID,
                    outcome: .recoveryRequired,
                    failedComponent: result.failedComponent,
                    errorCode: "lifecycle.rollbackFailed.\(failureCodes)",
                    effectiveSettings: currentSettings(fallback: restored)
                )
                activeRequest = TidyTapSettingsRequest(
                    settings: recoveryResult.effectiveSettings ?? restored,
                    applyRequestID: request.applyRequestID
                )
                let recoveredSettings = activeRequest?.settings ?? restored
                try? preferences.write(settings: recoveredSettings, applyRequestID: request.applyRequestID)
                report(recoveryResult)
                return recoveryResult
            }
            result = result.withEffectiveSettings(restored)
            activeRequest = TidyTapSettingsRequest(settings: restored, applyRequestID: request.applyRequestID)
            if restored != request.settings {
                try? preferences.write(settings: restored, applyRequestID: request.applyRequestID)
            }
        }

        report(result)
        let effective = result.effectiveSettings ?? request.settings
        if (result.outcome == .applied || result.outcome == .partiallyApplied), !effective.requiresHelper {
            terminator.terminate()
        }
        return result
    }

    private func apply(_ settings: TidyTapSettings, requestID: UUID) -> ApplyAttempt {
        var touchedComponents = [TidyTapApplyComponent]()

        do {
            try capsFeature.apply(capsLockEnabled: settings.capsLockInputSourceSwitching)
        } catch {
            return ApplyAttempt(
                status: failure(requestID, component: .capsLock, error: error),
                touchedComponents: touchedComponents
            )
        }
        touchedComponents.append(.capsLock)

        touchedComponents.append(.eventTap)
        let inputResult: TidyTapInputFeatureApplyResult
        do {
            inputResult = try inputFeatures.apply(
                reverseMouseWheel: settings.reverseMouseWheelVertically,
                sideButtonNavigation: settings.sideButtonNavigation,
                requestID: requestID
            )
        } catch {
            return ApplyAttempt(
                status: failure(requestID, component: .eventTap, error: error),
                touchedComponents: touchedComponents
            )
        }

        touchedComponents.append(.menuBar)
        do {
            try menuBar.applyMenuBar(visible: settings.showInMenuBar)
        } catch {
            return ApplyAttempt(
                status: failure(requestID, component: .menuBar, error: error),
                touchedComponents: touchedComponents
            )
        }

        switch inputResult {
        case .applied:
            return ApplyAttempt(status: .applied(requestID), touchedComponents: touchedComponents)
        case .partiallyApplied(let permissions):
            return ApplyAttempt(
                status: TidyTapApplyStatus(
                    applyRequestID: requestID,
                    outcome: .partiallyApplied,
                    failedComponent: .eventTap,
                    errorCode: "eventTap.permissionPartial.\(permissions.map(\.rawValue).sorted().joined(separator: "."))"
                ),
                touchedComponents: touchedComponents
            )
        }
    }

    /// The controllers themselves own their exact restoration details. Applying
    /// the captured previous snapshot in reverse order retains that ownership.
    /// Every touched component is attempted even when an earlier restoration
    /// step fails, leaving input in pass-through state wherever possible.
    private func restore(
        _ state: ControllerState,
        touchedComponents: [TidyTapApplyComponent],
        requestID: UUID
    ) -> [TidyTapApplyComponent] {
        var failures = [TidyTapApplyComponent]()

        if touchedComponents.contains(.menuBar) {
            do {
                try menuBar.applyMenuBar(visible: state.menuBarVisible)
            } catch {
                failures.append(.menuBar)
            }
        }

        if touchedComponents.contains(.eventTap) {
            do {
                _ = try inputFeatures.apply(
                    reverseMouseWheel: state.input.reverseMouseWheel,
                    sideButtonNavigation: state.input.sideButtonNavigation,
                    requestID: requestID
                )
            } catch {
                failures.append(.eventTap)
                do {
                    try inputFeatures.forcePassThrough()
                } catch {
                    // The tap controller could not even enter its safe mode.
                    // Keep one component code while retaining that fact in the
                    // recovery-required result.
                }
            }
        }

        if touchedComponents.contains(.capsLock) {
            do {
                try capsFeature.apply(capsLockEnabled: state.capsLockEnabled)
            } catch {
                failures.append(.capsLock)
            }
        }

        return failures
    }

    private struct ApplyAttempt {
        let status: TidyTapApplyStatus
        let touchedComponents: [TidyTapApplyComponent]
    }

    private func failure(
        _ requestID: UUID,
        component: TidyTapApplyComponent,
        error: Error,
        effectiveSettings: TidyTapSettings? = nil
    ) -> TidyTapApplyStatus {
        let code: String
        if case TidyTapInputFeatureAdapterError.permissionDenied(let permissions) = error {
            code = permissionCode(prefix: "\(component.rawValue).permissionDenied", permissions: permissions)
        } else if case TidyTapInputFeatureAdapterError.eventTapFailed = error {
            code = "\(component.rawValue).recoveryFailed"
        } else if let engineError = error as? InputEngineError {
            code = capsErrorCode(engineError, component: component)
        } else if let transaction = error as? TransactionFailure {
            let components = transaction.rollbackIssues.map(\.component.rawValue).joined(separator: ".")
            code = transaction.recoveryRequired
                ? "\(component.rawValue).recoveryRequired.\(components)"
                : "\(component.rawValue).transactionFailed"
        } else {
            code = "\(component.rawValue).applyFailed"
        }
        return TidyTapApplyStatus(
            applyRequestID: requestID,
            outcome: .failed,
            failedComponent: component,
            errorCode: code,
            effectiveSettings: effectiveSettings
        )
    }

    private func report(_ status: TidyTapApplyStatus) {
        try? preferences.writeApplyStatus(status)
        TidyTapIPC.postApplyResult(status)
    }

    private func effectiveSettings(_ requested: TidyTapSettings) -> TidyTapSettings {
        var effective = requested
        let input = inputFeatures.currentConfiguration()
        effective.reverseMouseWheelVertically = input.reverseMouseWheel
        effective.sideButtonNavigation = input.sideButtonNavigation
        return effective
    }

    private struct ControllerState {
        let capsLockEnabled: Bool
        let input: TidyTapInputFeatureConfiguration
        let menuBarVisible: Bool
    }

    private func captureControllerState() throws -> ControllerState {
        ControllerState(
            capsLockEnabled: try capsFeature.currentCapsLockEnabled(),
            input: inputFeatures.currentConfiguration(),
            menuBarVisible: menuBar.isMenuBarVisible
        )
    }

    private func settings(_ base: TidyTapSettings, applying state: ControllerState) -> TidyTapSettings {
        var result = base
        result.capsLockInputSourceSwitching = state.capsLockEnabled
        result.reverseMouseWheelVertically = state.input.reverseMouseWheel
        result.sideButtonNavigation = state.input.sideButtonNavigation
        result.showInMenuBar = state.menuBarVisible
        return result
    }

    private func currentSettings(fallback: TidyTapSettings) -> TidyTapSettings {
        guard let state = try? captureControllerState() else { return fallback }
        return settings(fallback, applying: state)
    }

    private func permissionCode(prefix: String, permissions: Set<TidyTapPermission>) -> String {
        "\(prefix).\(permissions.map(\.rawValue).sorted().joined(separator: "."))"
    }

    private func capsErrorCode(_ error: InputEngineError, component: TidyTapApplyComponent) -> String {
        let prefix = component.rawValue
        switch error {
        case .invalidInputSourceCount(let count): return "\(prefix).invalidInputSourceCount.\(count)"
        case .capsLockAlreadyMapped: return "\(prefix).conflict.sourceMapping"
        case .capsLockOwnershipConflict: return "\(prefix).conflict.hidOwnership"
        case .symbolicHotkeyOwnershipConflict: return "\(prefix).conflict.symbolicHotkey"
        case .staleSystemState(let engineComponent): return "\(prefix).recoveryRequired.\(engineComponent.rawValue)"
        default: return "\(prefix).applyFailed.\(String(describing: error))"
        }
    }
}

private extension TidyTapApplyStatus {
    func withEffectiveSettings(_ settings: TidyTapSettings) -> TidyTapApplyStatus {
        TidyTapApplyStatus(
            applyRequestID: applyRequestID,
            outcome: outcome,
            failedComponent: failedComponent,
            errorCode: errorCode,
            effectiveSettings: settings
        )
    }
}

final class ApplicationTerminator: TidyTapTerminating {
    func terminate() {
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
}
