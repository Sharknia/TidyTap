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
    var fixedMouseWheelStepEnabled: Bool
    var finderCutPasteEnabled: Bool
    /// This remains the user's remembered value even when the fixed-step
    /// capability is effectively off (for example after permission loss).
    var mouseWheelStepLines: Int

    init(
        reverseMouseWheel: Bool,
        sideButtonNavigation: Bool,
        fixedMouseWheelStepEnabled: Bool = false,
        finderCutPasteEnabled: Bool = false,
        mouseWheelStepLines: Int = TidyTapSettings.defaultMouseWheelStepLines
    ) {
        self.reverseMouseWheel = reverseMouseWheel
        self.sideButtonNavigation = sideButtonNavigation
        self.fixedMouseWheelStepEnabled = fixedMouseWheelStepEnabled
        self.finderCutPasteEnabled = finderCutPasteEnabled
        self.mouseWheelStepLines = mouseWheelStepLines
    }

    static let disabled = Self(
        reverseMouseWheel: false,
        sideButtonNavigation: false,
        fixedMouseWheelStepEnabled: false,
        finderCutPasteEnabled: false,
        mouseWheelStepLines: TidyTapSettings.defaultMouseWheelStepLines
    )
}

protocol TidyTapInputFeaturesApplying: AnyObject {
    func apply(
        reverseMouseWheel: Bool,
        sideButtonNavigation: Bool,
        fixedMouseWheelStepEnabled: Bool,
        finderCutPasteEnabled: Bool,
        mouseWheelStepLines: Int,
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

@MainActor
protocol TidyTapTerminating: AnyObject {
    func terminate()
    func terminate(ifCurrent: @escaping @MainActor () -> Bool)
}

extension TidyTapTerminating {
    func terminate(ifCurrent: @escaping @MainActor () -> Bool) {
        if ifCurrent() { terminate() }
    }
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
    private var lastReportedStatus: TidyTapApplyStatus?

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
        do {
            _ = try inputFeatures.apply(
                reverseMouseWheel: inputConfiguration.reverseMouseWheel,
                sideButtonNavigation: inputConfiguration.sideButtonNavigation,
                fixedMouseWheelStepEnabled: inputConfiguration.fixedMouseWheelStepEnabled,
                finderCutPasteEnabled: inputConfiguration.finderCutPasteEnabled,
                mouseWheelStepLines: activeRequest.settings.mouseWheelStepLines,
                requestID: requestID
            )
        } catch let adapterError as TidyTapInputFeatureAdapterError {
            runtimeResult = nil
            runtimeError = adapterError
        } catch {
            runtimeResult = nil
            runtimeError = .eventTapFailed
        }
        let normalizedInputConfiguration = inputFeatures.currentConfiguration()
        var effective = activeRequest.settings
        effective.reverseMouseWheelVertically = normalizedInputConfiguration.reverseMouseWheel
        effective.sideButtonNavigation = normalizedInputConfiguration.sideButtonNavigation
        effective.fixedMouseWheelStepEnabled = normalizedInputConfiguration.fixedMouseWheelStepEnabled
        effective.finderCutPasteEnabled = normalizedInputConfiguration.finderCutPasteEnabled
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
        // Launch-time application and its subsequent notification are the same
        // transaction. Do not turn a failed, sanitized request into a success.
        if let activeRequest, activeRequest.applyRequestID == request.applyRequestID,
           activeRequest.settings == request.settings, let lastReportedStatus,
           lastReportedStatus.outcome == .failed,
           lastReportedStatus.errorCode == "eventTap.creationFailed" {
            return lastReportedStatus
        }
        let previousState: ControllerState
        do {
            // A fresh adapter has not learned the persisted step yet. Seed the
            // rollback snapshot from the last confirmed request, or the first
            // persisted request, rather than its construction default.
            previousState = try captureControllerState(
                rememberedMouseWheelStepLines: activeRequest?.settings.mouseWheelStepLines
                    ?? request.settings.mouseWheelStepLines
            )
        } catch {
            let captureError = error as? ControllerStateCaptureError
            let result = failure(
                request.applyRequestID,
                component: captureError?.component ?? .lifecycle,
                error: captureError?.underlying ?? error,
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
        let recoveredCreationFailure = result.outcome == .failed &&
            result.failedComponent == .eventTap && result.errorCode == "eventTap.creationFailed"
        if (result.outcome == .applied || result.outcome == .partiallyApplied || recoveredCreationFailure), !effective.requiresHelper {
            terminateIfCurrent(request.applyRequestID)
        }
        return result
    }

    private func terminateIfCurrent(_ requestID: UUID) {
        terminator.terminate { [weak self] in
            guard let self, self.activeRequest?.applyRequestID == requestID else { return false }
            let latest = self.preferences.readRequest()
            guard latest.applyRequestID == requestID else {
                _ = self.apply(latest)
                return false
            }
            return true
        }
    }

    private func apply(_ settings: TidyTapSettings, requestID: UUID) -> ApplyAttempt {
        var touchedComponents = [TidyTapApplyComponent]()

        touchedComponents.append(.capsLock)
        do {
            try capsFeature.apply(capsLockEnabled: settings.capsLockInputSourceSwitching)
        } catch {
            return ApplyAttempt(
                status: failure(requestID, component: .capsLock, error: error),
                touchedComponents: touchedComponents
            )
        }
        touchedComponents.append(.eventTap)
        let inputResult: TidyTapInputFeatureApplyResult
        do {
            inputResult = try inputFeatures.apply(
                reverseMouseWheel: settings.reverseMouseWheelVertically,
                sideButtonNavigation: settings.sideButtonNavigation,
                fixedMouseWheelStepEnabled: settings.fixedMouseWheelStepEnabled,
                finderCutPasteEnabled: settings.finderCutPasteEnabled,
                mouseWheelStepLines: settings.mouseWheelStepLines,
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
            // Keep this narrow protocol for the existing transaction and
            // launch-smoke seams. The retired preference is always inert.
            try menuBar.applyMenuBar(visible: false)
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
                    fixedMouseWheelStepEnabled: state.input.fixedMouseWheelStepEnabled,
                    finderCutPasteEnabled: state.input.finderCutPasteEnabled,
                    mouseWheelStepLines: state.input.mouseWheelStepLines,
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
        let outcome: TidyTapApplyOutcome
        if case TidyTapInputFeatureAdapterError.permissionDenied(let permissions) = error {
            code = permissionCode(prefix: "\(component.rawValue).permissionDenied", permissions: permissions)
            outcome = .failed
        } else if case TidyTapInputFeatureAdapterError.eventTapFailed = error {
            code = "\(component.rawValue).recoveryFailed"
            outcome = .failed
        } else if case TidyTapInputFeatureAdapterError.engine(let engineError) = error {
            code = capsErrorCode(engineError, component: component)
            outcome = .failed
        } else if let engineError = error as? InputEngineError {
            code = capsErrorCode(engineError, component: component)
            outcome = .failed
        } else if let transaction = error as? TransactionFailure {
            let components = transaction.rollbackIssues.map(\.component.rawValue).joined(separator: ".")
            code = transaction.recoveryRequired
                ? "\(component.rawValue).recoveryRequired.\(components)"
                : "\(component.rawValue).transactionFailed"
            outcome = transaction.recoveryRequired ? .recoveryRequired : .failed
        } else {
            code = "\(component.rawValue).applyFailed"
            outcome = .failed
        }
        return TidyTapApplyStatus(
            applyRequestID: requestID,
            outcome: outcome,
            failedComponent: component,
            errorCode: code,
            effectiveSettings: effectiveSettings
        )
    }

    private func report(_ status: TidyTapApplyStatus) {
        lastReportedStatus = status
        try? preferences.writeApplyStatus(status)
        TidyTapIPC.postApplyResult(status)
    }

    private func effectiveSettings(_ requested: TidyTapSettings) -> TidyTapSettings {
        var effective = requested
        let input = inputFeatures.currentConfiguration()
        effective.reverseMouseWheelVertically = input.reverseMouseWheel
        effective.sideButtonNavigation = input.sideButtonNavigation
        effective.fixedMouseWheelStepEnabled = input.fixedMouseWheelStepEnabled
        effective.finderCutPasteEnabled = input.finderCutPasteEnabled
        return effective
    }

    private struct ControllerState {
        let capsLockEnabled: Bool
        let input: TidyTapInputFeatureConfiguration
        let menuBarVisible: Bool
    }

    private struct ControllerStateCaptureError: Error {
        let component: TidyTapApplyComponent
        let underlying: Error
    }

    private func captureControllerState(rememberedMouseWheelStepLines: Int? = nil) throws -> ControllerState {
        let capsLockEnabled: Bool
        do {
            capsLockEnabled = try capsFeature.currentCapsLockEnabled()
        } catch {
            throw ControllerStateCaptureError(component: .capsLock, underlying: error)
        }
        var input = inputFeatures.currentConfiguration()
        if let rememberedMouseWheelStepLines {
            input.mouseWheelStepLines = rememberedMouseWheelStepLines
        }
        return ControllerState(
            capsLockEnabled: capsLockEnabled,
            input: input,
            menuBarVisible: menuBar.isMenuBarVisible
        )
    }

    private func settings(_ base: TidyTapSettings, applying state: ControllerState) -> TidyTapSettings {
        var result = base
        result.capsLockInputSourceSwitching = state.capsLockEnabled
        result.reverseMouseWheelVertically = state.input.reverseMouseWheel
        result.sideButtonNavigation = state.input.sideButtonNavigation
        result.fixedMouseWheelStepEnabled = state.input.fixedMouseWheelStepEnabled
        result.finderCutPasteEnabled = state.input.finderCutPasteEnabled
        result.mouseWheelStepLines = state.input.mouseWheelStepLines
        return result
    }

    private func currentSettings(fallback: TidyTapSettings) -> TidyTapSettings {
        guard let state = try? captureControllerState(
            rememberedMouseWheelStepLines: activeRequest == nil ? fallback.mouseWheelStepLines : nil
        ) else { return fallback }
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
        case .preWriteStateChanged(let engineComponent): return "\(prefix).preWriteStateChanged.\(engineComponent.rawValue)"
        case .staleSystemState(let engineComponent): return "\(prefix).recoveryRequired.\(engineComponent.rawValue)"
        case .verificationFailed(let engineComponent): return "\(prefix).verificationFailed.\(engineComponent.rawValue)"
        case .invalidSystemData(let engineComponent): return "\(prefix).invalidSystemData.\(engineComponent.rawValue)"
        case .commandFailed: return "\(prefix).commandFailed"
        case .eventTapCreationFailed: return "\(prefix).creationFailed"
        case .eventTapRecoveryFailed: return "\(prefix).recoveryFailed"
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

@MainActor
final class ApplicationTerminator: TidyTapTerminating {
    private let setReadiness: (TidyTapWorkerLockOwner.Readiness) -> Bool
    private let enqueue: (@escaping @MainActor () -> Void) -> Void
    private let stop: () -> Void

    init(
        setReadiness: @escaping (TidyTapWorkerLockOwner.Readiness) -> Bool = { _ in true },
        enqueue: @escaping (@escaping @MainActor () -> Void) -> Void = { work in
            DispatchQueue.main.async { work() }
        },
        stop: @escaping () -> Void = { CFRunLoopStop(CFRunLoopGetMain()) }
    ) {
        self.setReadiness = setReadiness
        self.enqueue = enqueue
        self.stop = stop
    }

    func terminate() { terminate(ifCurrent: { true }) }

    func terminate(ifCurrent: @escaping @MainActor () -> Bool) {
        enqueue { [self] in
            // Publish before the final request read: a launcher must either
            // have already persisted its request or wait for this worker's exit.
            guard setReadiness(.stopping) else { return }
            guard ifCurrent() else {
                _ = setReadiness(.acknowledged)
                return
            }
            stop()
        }
    }
}
