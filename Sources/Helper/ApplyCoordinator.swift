import AppKit

/// Feature-specific implementations live in later stages. These narrow
/// interfaces keep the lifecycle transaction independent of CGEvent/HID APIs.
protocol TidyTapCapsFeatureApplying: AnyObject {
    func apply(capsLockEnabled: Bool) throws
}

protocol TidyTapInputFeaturesApplying: AnyObject {
    func apply(reverseMouseWheel: Bool, sideButtonNavigation: Bool) throws -> TidyTapInputFeatureApplyResult
    func forcePassThrough() throws
}

enum TidyTapInputFeatureApplyResult: Equatable {
    case applied
    case partiallyApplied(unavailablePermissions: Set<TidyTapPermission>)
}

protocol TidyTapMenuBarApplying: AnyObject {
    func applyMenuBar(visible: Bool) throws
}

protocol TidyTapTerminating: AnyObject {
    func terminate()
}

/// Runs the whole settings snapshot as one serial transaction. On any failure,
/// it reapplies the last known-good snapshot in reverse component order.
final class ApplyCoordinator {
    private let preferences: TidyTapPreferencesStoring
    private let capsFeature: TidyTapCapsFeatureApplying
    private let inputFeatures: TidyTapInputFeaturesApplying
    private let menuBar: TidyTapMenuBarApplying
    private let terminator: TidyTapTerminating
    private let lock = NSLock()
    private var activeSettings = TidyTapSettings.defaults

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

    @discardableResult
    func apply(_ request: TidyTapSettingsRequest) -> TidyTapApplyStatus {
        lock.lock()
        defer { lock.unlock() }

        let previousSettings = activeSettings
        let attempt = apply(request.settings, requestID: request.applyRequestID)
        let result = attempt.status
        if result.outcome == .applied || result.outcome == .partiallyApplied {
            activeSettings = request.settings
        } else {
            let rollbackFailures = restore(previousSettings, touchedComponents: attempt.touchedComponents)
            if !rollbackFailures.isEmpty {
                let failureCodes = rollbackFailures.map(\.rawValue).joined(separator: ".")
                let recoveryResult = TidyTapApplyStatus(
                    applyRequestID: request.applyRequestID,
                    outcome: .recoveryRequired,
                    failedComponent: result.failedComponent,
                    errorCode: "lifecycle.rollbackFailed.\(failureCodes)"
                )
                report(recoveryResult)
                return recoveryResult
            }
        }

        report(result)
        if (result.outcome == .applied || result.outcome == .partiallyApplied), !request.settings.requiresHelper {
            terminator.terminate()
        }
        return result
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
                sideButtonNavigation: settings.sideButtonNavigation
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
        _ settings: TidyTapSettings,
        touchedComponents: [TidyTapApplyComponent]
    ) -> [TidyTapApplyComponent] {
        var failures = [TidyTapApplyComponent]()

        if touchedComponents.contains(.menuBar) {
            do {
                try menuBar.applyMenuBar(visible: settings.showInMenuBar)
            } catch {
                failures.append(.menuBar)
            }
        }

        if touchedComponents.contains(.eventTap) {
            do {
                _ = try inputFeatures.apply(
                    reverseMouseWheel: settings.reverseMouseWheelVertically,
                    sideButtonNavigation: settings.sideButtonNavigation
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
                try capsFeature.apply(capsLockEnabled: settings.capsLockInputSourceSwitching)
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
        error: Error
    ) -> TidyTapApplyStatus {
        let code: String
        if case TidyTapInputFeatureAdapterError.permissionDenied(let permissions) = error {
            code = "\(component.rawValue).permissionDenied.\(permissions.map(\.rawValue).sorted().joined(separator: "."))"
        } else if case TidyTapInputFeatureAdapterError.eventTapFailed = error {
            code = "\(component.rawValue).recoveryFailed"
        } else {
            code = "\(component.rawValue).applyFailed"
        }
        return TidyTapApplyStatus(
            applyRequestID: requestID,
            outcome: .failed,
            failedComponent: component,
            errorCode: code
        )
    }

    private func report(_ status: TidyTapApplyStatus) {
        try? preferences.writeApplyStatus(status)
        TidyTapIPC.postApplyResult(status)
    }
}

final class ApplicationTerminator: TidyTapTerminating {
    func terminate() {
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
}
