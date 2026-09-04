import AppKit

/// Feature-specific implementations live in later stages. These narrow
/// interfaces keep the lifecycle transaction independent of CGEvent/HID APIs.
protocol TidyTapCapsFeatureApplying: AnyObject {
    func apply(capsLockEnabled: Bool) throws
}

protocol TidyTapInputFeaturesApplying: AnyObject {
    func apply(reverseMouseWheel: Bool, sideButtonNavigation: Bool) throws
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
        let result = apply(request.settings, requestID: request.applyRequestID)
        if result.outcome == .applied {
            activeSettings = request.settings
        } else if !restore(previousSettings) {
            let recoveryResult = TidyTapApplyStatus(
                applyRequestID: request.applyRequestID,
                outcome: .recoveryRequired,
                failedComponent: result.failedComponent,
                errorCode: "lifecycle.rollbackFailed"
            )
            report(recoveryResult)
            return recoveryResult
        }

        report(result)
        if result.outcome == .applied, !request.settings.requiresHelper {
            terminator.terminate()
        }
        return result
    }

    private func apply(_ settings: TidyTapSettings, requestID: UUID) -> TidyTapApplyStatus {
        do {
            try capsFeature.apply(capsLockEnabled: settings.capsLockInputSourceSwitching)
        } catch {
            return failure(requestID, component: .capsLock)
        }

        do {
            try inputFeatures.apply(
                reverseMouseWheel: settings.reverseMouseWheelVertically,
                sideButtonNavigation: settings.sideButtonNavigation
            )
        } catch {
            return failure(requestID, component: .eventTap)
        }

        do {
            try menuBar.applyMenuBar(visible: settings.showInMenuBar)
        } catch {
            return failure(requestID, component: .menuBar)
        }

        return .applied(requestID)
    }

    /// The controllers themselves own their exact restoration details. Applying
    /// the captured previous snapshot in reverse order retains that ownership.
    private func restore(_ settings: TidyTapSettings) -> Bool {
        do {
            try menuBar.applyMenuBar(visible: settings.showInMenuBar)
            try inputFeatures.apply(
                reverseMouseWheel: settings.reverseMouseWheelVertically,
                sideButtonNavigation: settings.sideButtonNavigation
            )
            try capsFeature.apply(capsLockEnabled: settings.capsLockInputSourceSwitching)
            return true
        } catch {
            return false
        }
    }

    private func failure(_ requestID: UUID, component: TidyTapApplyComponent) -> TidyTapApplyStatus {
        TidyTapApplyStatus(
            applyRequestID: requestID,
            outcome: .failed,
            failedComponent: component,
            errorCode: "\(component.rawValue).applyFailed"
        )
    }

    private func report(_ status: TidyTapApplyStatus) {
        try? preferences.writeApplyStatus(status)
        TidyTapIPC.postApplyResult(status)
    }
}

final class NoopCapsFeature: TidyTapCapsFeatureApplying {
    func apply(capsLockEnabled: Bool) throws {}
}

final class NoopInputFeatures: TidyTapInputFeaturesApplying {
    func apply(reverseMouseWheel: Bool, sideButtonNavigation: Bool) throws {}
}

final class ApplicationTerminator: TidyTapTerminating {
    func terminate() {
        DispatchQueue.main.async {
            NSApplication.shared.terminate(nil)
        }
    }
}
