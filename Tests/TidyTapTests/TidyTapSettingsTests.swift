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
        XCTAssertEqual(calls.values, ["caps:true", "input:true:false", "menu:false", "input:false:false", "caps:false"])
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
}

private final class InMemoryPreferences: TidyTapPreferencesStoring {
    var request: TidyTapSettingsRequest
    var status: TidyTapApplyStatus?

    init(request: TidyTapSettingsRequest) {
        self.request = request
    }

    func readRequest() -> TidyTapSettingsRequest { request }
    func write(settings: TidyTapSettings, applyRequestID: UUID) throws {
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
}

private final class RecordingMenu: TidyTapMenuBarApplying {
    let calls: CallLog
    init(calls: CallLog) { self.calls = calls }
    func applyMenuBar(visible: Bool) throws { calls.values.append("menu:\(visible)") }
}

private final class RecordingTerminator: TidyTapTerminating {
    let calls: CallLog
    init(calls: CallLog) { self.calls = calls }
    func terminate() { calls.values.append("terminate") }
}

private enum TestError: Error {
    case failure
}
