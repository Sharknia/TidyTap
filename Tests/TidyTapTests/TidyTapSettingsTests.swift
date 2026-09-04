import XCTest

final class TidyTapSettingsTests: XCTestCase {
    func testDefaultSettingsKeepEveryCapabilityDisabled() {
        XCTAssertEqual(TidyTapSettings.defaults, TidyTapSettings(
            capsLockInputSourceSwitching: false,
            reverseMouseWheelVertically: false,
            sideButtonNavigation: false,
            launchAtLogin: false,
            showInMenuBar: false
        ))
    }

    func testBundleIdentifiersUseTheTidyTapNamespace() {
        XCTAssertEqual(TidyTapProduct.appBundleIdentifier, "com.sharknia.TidyTap")
        XCTAssertEqual(TidyTapProduct.helperBundleIdentifier, "com.sharknia.TidyTap.Helper")
    }

    func testOnlyCoreFeaturesAndMenuBarKeepHelperAlive() {
        XCTAssertFalse(TidyTapSettings.defaults.requiresHelper)

        var settings = TidyTapSettings.defaults
        settings.launchAtLogin = true
        XCTAssertFalse(settings.requiresHelper)

        settings.showInMenuBar = true
        XCTAssertTrue(settings.requiresHelper)
    }

    func testMouseWheelNeedsAccessibilityAndInputMonitoring() {
        let denied = TidyTapFeaturePermissionState(
            accessibility: .authorized,
            inputMonitoring: .denied
        )
        XCTAssertFalse(denied.isAuthorized(for: .mouseWheel))
        XCTAssertTrue(denied.isAuthorized(for: .sideButtonNavigation))
        XCTAssertTrue(denied.isAuthorized(for: .capsLock))

        let authorized = TidyTapFeaturePermissionState(
            accessibility: .authorized,
            inputMonitoring: .authorized
        )
        XCTAssertTrue(authorized.isAuthorized(for: .mouseWheel))
    }

    func testApplyCoordinatorRollsBackInReverseOrderAfterInputFailure() {
        let requestID = UUID()
        let store = InMemoryPreferences(request: TidyTapSettingsRequest(
            settings: TidyTapSettings(
                capsLockInputSourceSwitching: true,
                reverseMouseWheelVertically: true,
                sideButtonNavigation: false,
                launchAtLogin: false,
                showInMenuBar: false
            ),
            applyRequestID: requestID
        ))
        let calls = CallLog()
        let coordinator = ApplyCoordinator(
            preferences: store,
            capsFeature: RecordingCaps(calls: calls),
            inputFeatures: FailingInput(calls: calls),
            menuBar: RecordingMenu(calls: calls),
            terminator: RecordingTerminator(calls: calls)
        )

        let status = coordinator.applyLatestSettings()

        XCTAssertEqual(status.outcome, .failed)
        XCTAssertEqual(status.failedComponent, .eventTap)
        XCTAssertEqual(status.applyRequestID, requestID)
        XCTAssertEqual(store.status, status)
        XCTAssertEqual(calls.values, ["caps:true", "input:true:false", "input:false:false", "caps:false"])
    }

    func testAllOffApplyTerminatesOnlyAfterSuccess() {
        let requestID = UUID()
        let store = InMemoryPreferences(request: TidyTapSettingsRequest(settings: .defaults, applyRequestID: requestID))
        let calls = CallLog()
        let coordinator = ApplyCoordinator(
            preferences: store,
            capsFeature: RecordingCaps(calls: calls),
            inputFeatures: RecordingInput(calls: calls),
            menuBar: RecordingMenu(calls: calls),
            terminator: RecordingTerminator(calls: calls)
        )

        XCTAssertEqual(coordinator.applyLatestSettings().outcome, .applied)
        XCTAssertEqual(calls.values.last, "terminate")
    }

    func testMenuRollbackFailureStillRestoresInputAndCaps() {
        let requestID = UUID()
        let store = InMemoryPreferences(request: TidyTapSettingsRequest(
            settings: enabledSettings(showInMenuBar: true),
            applyRequestID: requestID
        ))
        let calls = CallLog()
        let coordinator = ApplyCoordinator(
            preferences: store,
            capsFeature: RecordingCaps(calls: calls),
            inputFeatures: RecordingInput(calls: calls),
            menuBar: FailingMenu(calls: calls, failWhenVisible: true, failWhenHidden: true),
            terminator: RecordingTerminator(calls: calls)
        )

        let status = coordinator.applyLatestSettings()

        XCTAssertEqual(status.outcome, .recoveryRequired)
        XCTAssertEqual(status.errorCode, "lifecycle.rollbackFailed.menuBar")
        XCTAssertEqual(calls.values, [
            "caps:true", "input:true:false", "menu:true",
            "menu:false", "input:false:false", "caps:false"
        ])
    }

    func testInputRollbackFailureForcesPassThroughAndStillRestoresCaps() {
        let requestID = UUID()
        let store = InMemoryPreferences(request: TidyTapSettingsRequest(
            settings: enabledSettings(showInMenuBar: true),
            applyRequestID: requestID
        ))
        let calls = CallLog()
        let coordinator = ApplyCoordinator(
            preferences: store,
            capsFeature: RecordingCaps(calls: calls),
            inputFeatures: FailingRollbackInput(calls: calls),
            menuBar: FailingMenu(calls: calls, failWhenVisible: true, failWhenHidden: false),
            terminator: RecordingTerminator(calls: calls)
        )

        let status = coordinator.applyLatestSettings()

        XCTAssertEqual(status.outcome, .recoveryRequired)
        XCTAssertEqual(status.errorCode, "lifecycle.rollbackFailed.eventTap")
        XCTAssertEqual(calls.values, [
            "caps:true", "input:true:false", "menu:true",
            "menu:false", "input:false:false", "input:passThrough", "caps:false"
        ])
    }

    func testRollbackReportsEveryComponentThatCouldNotBeRestored() {
        let requestID = UUID()
        let store = InMemoryPreferences(request: TidyTapSettingsRequest(
            settings: enabledSettings(showInMenuBar: true),
            applyRequestID: requestID
        ))
        let calls = CallLog()
        let coordinator = ApplyCoordinator(
            preferences: store,
            capsFeature: RecordingCaps(calls: calls),
            inputFeatures: FailingRollbackInput(calls: calls),
            menuBar: FailingMenu(calls: calls, failWhenVisible: true, failWhenHidden: true),
            terminator: RecordingTerminator(calls: calls)
        )

        let status = coordinator.applyLatestSettings()

        XCTAssertEqual(status.outcome, .recoveryRequired)
        XCTAssertEqual(status.errorCode, "lifecycle.rollbackFailed.menuBar.eventTap")
        XCTAssertEqual(calls.values.last, "caps:false")
    }

    func testRegisterFailureDoesNotPersistOrLaunchNewSettings() {
        let original = TidyTapSettings(
            capsLockInputSourceSwitching: true,
            reverseMouseWheelVertically: false,
            sideButtonNavigation: false,
            launchAtLogin: false,
            showInMenuBar: false
        )
        let store = InMemoryPreferences(request: TidyTapSettingsRequest(settings: original, applyRequestID: UUID()))
        let launcher = RecordingHelperLauncher()
        let loginItem = FailingLoginItem(failingEnabledValue: true)
        let coordinator = SettingsCoordinator(
            preferences: store,
            helperLauncher: launcher,
            loginItemManager: loginItem
        )

        var requested = original
        requested.launchAtLogin = true

        XCTAssertThrowsError(try coordinator.save(requested))
        XCTAssertEqual(store.request.settings, original)
        XCTAssertNil(coordinator.latestRequestID)
        XCTAssertNil(coordinator.latestApplyStatus)
        XCTAssertEqual(loginItem.values, [true])
        XCTAssertEqual(launcher.launchCount, 0)
    }

    func testUnregisterFailureDoesNotPersistOrDeactivateRunningHelper() {
        let original = TidyTapSettings(
            capsLockInputSourceSwitching: true,
            reverseMouseWheelVertically: false,
            sideButtonNavigation: false,
            launchAtLogin: true,
            showInMenuBar: false
        )
        let store = InMemoryPreferences(request: TidyTapSettingsRequest(settings: original, applyRequestID: UUID()))
        let launcher = RecordingHelperLauncher()
        let loginItem = FailingLoginItem(failingEnabledValue: false)
        let coordinator = SettingsCoordinator(
            preferences: store,
            helperLauncher: launcher,
            loginItemManager: loginItem
        )

        var requested = original
        requested.capsLockInputSourceSwitching = false
        requested.launchAtLogin = false

        XCTAssertThrowsError(try coordinator.save(requested))
        XCTAssertEqual(store.request.settings, original)
        XCTAssertNil(coordinator.latestRequestID)
        XCTAssertNil(coordinator.latestApplyStatus)
        XCTAssertEqual(loginItem.values, [false])
        XCTAssertEqual(launcher.launchCount, 0)
    }

    func testPersistenceFailureAndRegisterCompensationFailureReportsBothErrors() {
        let original = TidyTapSettings.defaults
        let store = InMemoryPreferences(
            request: TidyTapSettingsRequest(settings: original, applyRequestID: UUID()),
            writeError: TestError.persistence
        )
        let loginItem = FailingLoginItem(failingValues: [false])
        let coordinator = SettingsCoordinator(
            preferences: store,
            helperLauncher: RecordingHelperLauncher(),
            loginItemManager: loginItem
        )

        var requested = original
        requested.launchAtLogin = true

        XCTAssertThrowsError(try coordinator.save(requested)) { error in
            guard let recoveryError = error as? TidyTapSettingsRecoveryRequiredError else {
                return XCTFail("Expected TidyTapSettingsRecoveryRequiredError, got \(error)")
            }
            XCTAssertEqual(recoveryError.persistenceError as? TestError, .persistence)
            XCTAssertEqual(recoveryError.loginItemRecoveryError as? TestError, .recovery)
        }
        XCTAssertEqual(store.request.settings, original)
        XCTAssertEqual(loginItem.values, [true, false])
    }

    func testPersistenceFailureAndUnregisterCompensationFailureReportsBothErrors() {
        var original = TidyTapSettings.defaults
        original.launchAtLogin = true
        let store = InMemoryPreferences(
            request: TidyTapSettingsRequest(settings: original, applyRequestID: UUID()),
            writeError: TestError.persistence
        )
        let loginItem = FailingLoginItem(failingValues: [true])
        let coordinator = SettingsCoordinator(
            preferences: store,
            helperLauncher: RecordingHelperLauncher(),
            loginItemManager: loginItem
        )

        var requested = original
        requested.launchAtLogin = false

        XCTAssertThrowsError(try coordinator.save(requested)) { error in
            guard let recoveryError = error as? TidyTapSettingsRecoveryRequiredError else {
                return XCTFail("Expected TidyTapSettingsRecoveryRequiredError, got \(error)")
            }
            XCTAssertEqual(recoveryError.persistenceError as? TestError, .persistence)
            XCTAssertEqual(recoveryError.loginItemRecoveryError as? TestError, .recovery)
        }
        XCTAssertEqual(store.request.settings, original)
        XCTAssertEqual(loginItem.values, [false, true])
    }

    private func enabledSettings(showInMenuBar: Bool) -> TidyTapSettings {
        TidyTapSettings(
            capsLockInputSourceSwitching: true,
            reverseMouseWheelVertically: true,
            sideButtonNavigation: false,
            launchAtLogin: false,
            showInMenuBar: showInMenuBar
        )
    }
}

private final class InMemoryPreferences: TidyTapPreferencesStoring {
    var request: TidyTapSettingsRequest
    var status: TidyTapApplyStatus?
    var writeError: Error?

    init(request: TidyTapSettingsRequest, writeError: Error? = nil) {
        self.request = request
        self.writeError = writeError
    }

    func readRequest() -> TidyTapSettingsRequest { request }
    func write(settings: TidyTapSettings, applyRequestID: UUID) throws {
        if let writeError {
            throw writeError
        }
        request = TidyTapSettingsRequest(settings: settings, applyRequestID: applyRequestID)
        status = .pending(applyRequestID)
    }
    func readApplyStatus() -> TidyTapApplyStatus? { status }
    func writeApplyStatus(_ status: TidyTapApplyStatus) throws { self.status = status }
}

private final class CallLog {
    var values = [String]()
}

private final class RecordingCaps: TidyTapCapsFeatureApplying {
    let calls: CallLog
    init(calls: CallLog) { self.calls = calls }
    func apply(capsLockEnabled: Bool) throws { calls.values.append("caps:\(capsLockEnabled)") }
}

private final class RecordingInput: TidyTapInputFeaturesApplying {
    let calls: CallLog
    init(calls: CallLog) { self.calls = calls }
    func apply(reverseMouseWheel: Bool, sideButtonNavigation: Bool) throws {
        calls.values.append("input:\(reverseMouseWheel):\(sideButtonNavigation)")
    }
    func forcePassThrough() throws { calls.values.append("input:passThrough") }
}

private final class FailingInput: TidyTapInputFeaturesApplying {
    let calls: CallLog
    init(calls: CallLog) { self.calls = calls }
    func apply(reverseMouseWheel: Bool, sideButtonNavigation: Bool) throws {
        calls.values.append("input:\(reverseMouseWheel):\(sideButtonNavigation)")
        if reverseMouseWheel {
            throw TestError.failure
        }
    }
    func forcePassThrough() throws { calls.values.append("input:passThrough") }
}

private final class FailingRollbackInput: TidyTapInputFeaturesApplying {
    let calls: CallLog
    init(calls: CallLog) { self.calls = calls }
    func apply(reverseMouseWheel: Bool, sideButtonNavigation: Bool) throws {
        calls.values.append("input:\(reverseMouseWheel):\(sideButtonNavigation)")
        if !reverseMouseWheel {
            throw TestError.failure
        }
    }
    func forcePassThrough() throws { calls.values.append("input:passThrough") }
}

private final class RecordingMenu: TidyTapMenuBarApplying {
    let calls: CallLog
    init(calls: CallLog) { self.calls = calls }
    func applyMenuBar(visible: Bool) throws { calls.values.append("menu:\(visible)") }
}

private final class FailingMenu: TidyTapMenuBarApplying {
    let calls: CallLog
    let failWhenVisible: Bool
    let failWhenHidden: Bool

    init(calls: CallLog, failWhenVisible: Bool, failWhenHidden: Bool) {
        self.calls = calls
        self.failWhenVisible = failWhenVisible
        self.failWhenHidden = failWhenHidden
    }

    func applyMenuBar(visible: Bool) throws {
        calls.values.append("menu:\(visible)")
        if visible ? failWhenVisible : failWhenHidden {
            throw TestError.failure
        }
    }
}

private final class RecordingTerminator: TidyTapTerminating {
    let calls: CallLog
    init(calls: CallLog) { self.calls = calls }
    func terminate() { calls.values.append("terminate") }
}

private final class RecordingHelperLauncher: TidyTapHelperLaunching {
    private(set) var launchCount = 0
    func launchOrActivateHelper() { launchCount += 1 }
}

private final class FailingLoginItem: TidyTapLoginItemManaging {
    let failingValues: Set<Bool>
    private(set) var values = [Bool]()

    convenience init(failingEnabledValue: Bool) {
        self.init(failingValues: [failingEnabledValue])
    }

    init(failingValues: Set<Bool>) {
        self.failingValues = failingValues
    }

    func setEnabled(_ enabled: Bool) throws {
        values.append(enabled)
        if failingValues.contains(enabled) {
            throw enabled ? TestError.recovery : TestError.recovery
        }
    }

    func status() -> TidyTapLoginItemStatus { .disabled }
}

private enum TestError: Error, Equatable {
    case failure
    case persistence
    case recovery
}
