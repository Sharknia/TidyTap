import XCTest
import TidyTapInputEngine

@MainActor
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

    func testCorrelatedFailedApplyRestoresVisiblePersistedSnapshotWithoutSecondSubmission() throws {
        let original = TidyTapSettings.defaults
        let store = InMemoryPreferences(request: .init(settings: original, applyRequestID: UUID()))
        let coordinator = SettingsCoordinator(
            preferences: store,
            helperLauncher: RecordingHelperLauncher(),
            loginItemManager: FailingLoginItem(failingValues: [])
        )
        var requested = original
        requested.sideButtonNavigation = true
        let requestID = try coordinator.save(requested)
        let failed = TidyTapApplyStatus(
            applyRequestID: requestID,
            outcome: .failed,
            failedComponent: .eventTap,
            errorCode: "eventTap.permissionDenied.accessibility"
        )
        try store.writeApplyStatus(failed)

        XCTAssertEqual(coordinator.receiveApplyResult(), failed)
        XCTAssertEqual(coordinator.visibleSettings(for: failed), original)
        XCTAssertEqual(store.request.settings, requested, "UI rollback must not submit a second request")
    }

    func testPartialInputPermissionIsReportedWithTheRequestID() {
        let requestID = UUID()
        let settings = TidyTapSettings(
            capsLockInputSourceSwitching: false,
            reverseMouseWheelVertically: true,
            sideButtonNavigation: true,
            launchAtLogin: false,
            showInMenuBar: false
        )
        let store = InMemoryPreferences(request: .init(settings: settings, applyRequestID: requestID))
        let coordinator = ApplyCoordinator(
            preferences: store,
            capsFeature: RecordingCaps(calls: CallLog()),
            inputFeatures: PartialInput(),
            menuBar: RecordingMenu(calls: CallLog()),
            terminator: RecordingTerminator(calls: CallLog())
        )

        let result = coordinator.applyLatestSettings()

        XCTAssertEqual(result.applyRequestID, requestID)
        XCTAssertEqual(result.outcome, .partiallyApplied)
        XCTAssertEqual(result.errorCode, "eventTap.permissionPartial.inputMonitoring")
    }

    func testInputAdapterRetainsSideButtonsForInputMonitoringPartialState() throws {
        let permissions = FakeInputPermissions(accessibility: true, inputMonitoring: false)
        let backend = FakeEventTapBackend()
        let adapter = InputFeaturesAdapter(
            permissionChecker: permissions,
            backend: backend,
            sideButtons: SideButtonController(
                applicationProvider: FakeFocusedProvider(),
                synthesizer: FakeNavigationSynthesizer()
            )
        )

        let result = try adapter.apply(
            reverseMouseWheel: true,
            sideButtonNavigation: true,
            requestID: UUID()
        )

        XCTAssertEqual(result, .partiallyApplied(unavailablePermissions: [.inputMonitoring]))
        XCTAssertEqual(backend.configurations, [.init(reverseMouseScroll: false, sideButtonNavigation: true)])
        XCTAssertEqual(backend.captureSideButtons, [true])
    }

    func testCapsAdapterPersistsEngineOwnershipThenRestoresOnlyItsOwnedValues() throws {
        let system = FakeCapsSystem()
        let ownership = InMemoryCapsOwnership()
        let controller = CapsLockFeatureController(
            hid: CapsLockController(system: system),
            hotkey: InputSourceShortcutController(system: system),
            inputSources: system
        )
        let adapter = CapsLockFeatureAdapter(controller: controller, ownershipStore: ownership)

        try adapter.apply(capsLockEnabled: true)
        XCTAssertEqual(system.mappings, [.tidyTapCapsLock])
        XCTAssertEqual(InputSourceShortcutController.hotkey60(in: system.domain), .tidyTapHotkey60)
        XCTAssertNotNil(ownership.data)

        try adapter.apply(capsLockEnabled: false)
        XCTAssertTrue(system.mappings.isEmpty)
        XCTAssertNil(InputSourceShortcutController.hotkey60(in: system.domain))
        XCTAssertNil(ownership.data)
    }

    func testCapsAdapterRecoversRebootWhenHotkeySurvivesAndHIDResets() throws {
        let system = FakeCapsSystem()
        let ownership = InMemoryCapsOwnership()
        let adapter = makeCapsAdapter(system: system, ownership: ownership)
        try adapter.apply(capsLockEnabled: true)
        system.mappings = []

        let restarted = makeCapsAdapter(system: system, ownership: ownership)
        try restarted.apply(capsLockEnabled: true)

        XCTAssertEqual(system.mappings, [.tidyTapCapsLock])
        XCTAssertEqual(InputSourceShortcutController.hotkey60(in: system.domain), .tidyTapHotkey60)
    }

    func testCapsAdapterCompletesPreparedJournalAfterHIDOnlyCrash() throws {
        let system = FakeCapsSystem()
        let ownership = InMemoryCapsOwnership()
        let controller = makeCapsController(system: system)
        let plan = try controller.prepareEnablePlan()
        system.mappings = plan.hid.after
        ownership.data = try JSONEncoder().encode(CapsJournal(
            enabled: true,
            phase: .prepared,
            ownership: try XCTUnwrap(plan.ownership),
            enablePlan: plan
        ))

        try makeCapsAdapter(system: system, ownership: ownership).apply(capsLockEnabled: true)

        XCTAssertEqual(system.mappings, plan.hid.after)
        XCTAssertEqual(system.domain, plan.hotkey60.after)
        XCTAssertEqual(system.activationCount, 1)
    }

    func testCapsAdapterReactivatesPreparedJournalAfterHotkeyWriteCrash() throws {
        let system = FakeCapsSystem()
        let ownership = InMemoryCapsOwnership()
        let controller = makeCapsController(system: system)
        let plan = try controller.prepareEnablePlan()
        system.mappings = plan.hid.after
        system.domain = plan.hotkey60.after
        ownership.data = try JSONEncoder().encode(CapsJournal(
            enabled: true,
            phase: .prepared,
            ownership: try XCTUnwrap(plan.ownership),
            enablePlan: plan
        ))

        try makeCapsAdapter(system: system, ownership: ownership).apply(capsLockEnabled: true)

        XCTAssertEqual(system.activationCount, 1)
    }

    func testSynchronousInstallStatusIsSuppressedUntilApplyReturns() throws {
        let requestID = UUID()
        let backend = FakeEventTapBackend()
        backend.synchronousInputOnInstall = .disabled(.timeout)
        let adapter = InputFeaturesAdapter(
            permissionChecker: FakeInputPermissions(accessibility: true, inputMonitoring: true),
            backend: backend,
            sideButtons: SideButtonController(
                applicationProvider: FakeFocusedProvider(),
                synthesizer: FakeNavigationSynthesizer()
            )
        )
        var runtimeRequestIDs = [UUID]()
        adapter.runtimeStatusHandler = { id, _, _ in runtimeRequestIDs.append(id) }

        XCTAssertEqual(
            try adapter.apply(reverseMouseWheel: true, sideButtonNavigation: false, requestID: requestID),
            .applied
        )
        XCTAssertTrue(runtimeRequestIDs.isEmpty, "install-time callback must not reenter ApplyCoordinator")

        _ = backend.send(.disabled(.timeout))
        XCTAssertEqual(runtimeRequestIDs, [requestID])
    }

    func testFullPermissionDenialLeavesEnginePersistedSettingsAndStatusAllOff() {
        let requestID = UUID()
        let requested = TidyTapSettings(
            capsLockInputSourceSwitching: false,
            reverseMouseWheelVertically: true,
            sideButtonNavigation: true,
            launchAtLogin: false,
            showInMenuBar: false
        )
        let store = InMemoryPreferences(request: .init(settings: requested, applyRequestID: requestID))
        let backend = FakeEventTapBackend()
        let input = InputFeaturesAdapter(
            permissionChecker: FakeInputPermissions(accessibility: false, inputMonitoring: false),
            backend: backend,
            sideButtons: SideButtonController(
                applicationProvider: FakeFocusedProvider(),
                synthesizer: FakeNavigationSynthesizer()
            )
        )
        let coordinator = ApplyCoordinator(
            preferences: store,
            capsFeature: RecordingCaps(calls: CallLog()),
            inputFeatures: input,
            menuBar: RecordingMenu(calls: CallLog()),
            terminator: RecordingTerminator(calls: CallLog())
        )

        let status = coordinator.applyLatestSettings()

        XCTAssertEqual(status.outcome, .partiallyApplied)
        XCTAssertEqual(status.errorCode, "eventTap.permissionPartial.accessibility.inputMonitoring")
        XCTAssertEqual(input.currentConfiguration(), .disabled)
        XCTAssertFalse(store.request.settings.reverseMouseWheelVertically)
        XCTAssertFalse(store.request.settings.sideButtonNavigation)
        XCTAssertEqual(status.effectiveSettings, store.request.settings)
    }

    func testPartialPermissionLeavesOnlySideButtonsEffectiveEverywhere() {
        let requestID = UUID()
        let requested = TidyTapSettings(
            capsLockInputSourceSwitching: false,
            reverseMouseWheelVertically: true,
            sideButtonNavigation: true,
            launchAtLogin: false,
            showInMenuBar: false
        )
        let store = InMemoryPreferences(request: .init(settings: requested, applyRequestID: requestID))
        let input = PartialInput()
        let coordinator = ApplyCoordinator(
            preferences: store,
            capsFeature: RecordingCaps(calls: CallLog()),
            inputFeatures: input,
            menuBar: RecordingMenu(calls: CallLog()),
            terminator: RecordingTerminator(calls: CallLog())
        )

        let status = coordinator.applyLatestSettings()

        XCTAssertEqual(input.currentConfiguration(), .init(reverseMouseWheel: false, sideButtonNavigation: true))
        XCTAssertEqual(status.effectiveSettings?.reverseMouseWheelVertically, false)
        XCTAssertEqual(status.effectiveSettings?.sideButtonNavigation, true)
        XCTAssertEqual(store.request.settings, status.effectiveSettings)
    }

    func testRuntimeStatusKeepsProducingRequestIDWhenNewerRequestIsPersisted() {
        let firstID = UUID()
        var first = TidyTapSettings.defaults
        first.sideButtonNavigation = true
        let store = InMemoryPreferences(request: .init(settings: first, applyRequestID: firstID))
        let input = RecordingInput(calls: CallLog())
        let coordinator = ApplyCoordinator(
            preferences: store,
            capsFeature: RecordingCaps(calls: CallLog()),
            inputFeatures: input,
            menuBar: RecordingMenu(calls: CallLog()),
            terminator: RecordingTerminator(calls: CallLog())
        )
        _ = coordinator.applyLatestSettings()
        let newerID = UUID()
        var newer = first
        newer.showInMenuBar = true
        store.request = .init(settings: newer, applyRequestID: newerID)
        input.configuration = .disabled

        coordinator.reportRuntimeInput(
            requestID: firstID,
            .partiallyApplied(unavailablePermissions: [.accessibility]),
            error: nil
        )

        XCTAssertEqual(store.status?.applyRequestID, firstID)
        XCTAssertEqual(store.request.applyRequestID, newerID)
        XCTAssertEqual(store.request.settings, newer, "an older runtime result must not rewrite the newer request")
        coordinator.reportRuntimeInput(requestID: UUID(), .applied, error: nil)
        XCTAssertEqual(store.status?.applyRequestID, firstID, "unknown runtime generations are ignored")
    }

    func testRollbackUsesActualControllerStateAfterHelperRestart() {
        let requestID = UUID()
        let requested = TidyTapSettings.defaults
        let calls = CallLog()
        let caps = RecordingCaps(calls: calls, enabled: true)
        let input = RecordingInput(
            calls: calls,
            configuration: .init(reverseMouseWheel: false, sideButtonNavigation: true)
        )
        let menu = FailingMenu(
            calls: calls,
            failWhenVisible: false,
            failWhenHidden: true,
            initiallyVisible: true
        )
        let store = InMemoryPreferences(request: .init(settings: requested, applyRequestID: requestID))
        let coordinator = ApplyCoordinator(
            preferences: store,
            capsFeature: caps,
            inputFeatures: input,
            menuBar: menu,
            terminator: RecordingTerminator(calls: calls)
        )

        let result = coordinator.applyLatestSettings()

        XCTAssertEqual(result.outcome, .failed)
        XCTAssertEqual(calls.values, [
            "caps:false", "input:false:false", "menu:false",
            "menu:true", "input:false:true", "caps:true"
        ])
        XCTAssertTrue(caps.enabled)
        XCTAssertEqual(input.configuration, .init(reverseMouseWheel: false, sideButtonNavigation: true))
        XCTAssertTrue(menu.isMenuBarVisible)
    }

    func testStartupUsesCorrelatedPersistedEffectiveStatus() {
        let requestID = UUID()
        var requested = TidyTapSettings.defaults
        requested.reverseMouseWheelVertically = true
        var effective = requested
        effective.reverseMouseWheelVertically = false
        let store = InMemoryPreferences(request: .init(settings: requested, applyRequestID: requestID))
        store.status = TidyTapApplyStatus(
            applyRequestID: requestID,
            outcome: .partiallyApplied,
            failedComponent: .eventTap,
            errorCode: "eventTap.permissionPartial.inputMonitoring",
            effectiveSettings: effective
        )
        let coordinator = SettingsCoordinator(
            preferences: store,
            helperLauncher: RecordingHelperLauncher(),
            loginItemManager: StatefulLoginItem(status: .disabled)
        )

        coordinator.restoreSession()

        XCTAssertEqual(coordinator.latestApplyStatus, store.status)
        XCTAssertEqual(coordinator.settingsForUI(), effective)
    }

    func testApplyResultAlwaysRenormalizesLoginItemFromLiveServiceTruth() {
        let requestID = UUID()
        var persisted = TidyTapSettings.defaults
        persisted.launchAtLogin = true
        let store = InMemoryPreferences(request: .init(settings: persisted, applyRequestID: requestID))
        let status = TidyTapApplyStatus.applied(requestID, effectiveSettings: persisted)
        store.status = status
        let coordinator = SettingsCoordinator(
            preferences: store,
            helperLauncher: RecordingHelperLauncher(),
            loginItemManager: StatefulLoginItem(status: .requiresApproval)
        )

        XCTAssertFalse(coordinator.visibleSettings(for: status).launchAtLogin)
    }

    func testCapsErrorsMapToStableSpecificUICodes() {
        let cases: [(Error, String)] = [
            (InputEngineError.invalidInputSourceCount(3), "capsLock.invalidInputSourceCount.3"),
            (InputEngineError.capsLockAlreadyMapped, "capsLock.conflict.sourceMapping"),
            (InputEngineError.capsLockOwnershipConflict, "capsLock.conflict.hidOwnership"),
            (InputEngineError.symbolicHotkeyOwnershipConflict, "capsLock.conflict.symbolicHotkey"),
            (InputEngineError.staleSystemState(.hidMappings), "capsLock.recoveryRequired.hidMappings"),
            (TransactionFailure(
                primaryDescription: "failed",
                rollbackIssues: [.init(component: .symbolicHotkey60, description: "failed")]
            ), "capsLock.recoveryRequired.symbolicHotkey60")
        ]

        for (error, expectedCode) in cases {
            let requestID = UUID()
            var settings = TidyTapSettings.defaults
            settings.capsLockInputSourceSwitching = true
            let coordinator = ApplyCoordinator(
                preferences: InMemoryPreferences(request: .init(settings: settings, applyRequestID: requestID)),
                capsFeature: ThrowingCaps(error: error),
                inputFeatures: RecordingInput(calls: CallLog()),
                menuBar: RecordingMenu(calls: CallLog()),
                terminator: RecordingTerminator(calls: CallLog())
            )
            XCTAssertEqual(coordinator.applyLatestSettings().errorCode, expectedCode)
        }
    }

    func testAllOffStillLaunchesStoppedHelperForDurableCleanup() throws {
        let store = InMemoryPreferences(request: .init(settings: .defaults, applyRequestID: UUID()))
        let launcher = RecordingHelperLauncher()
        let coordinator = SettingsCoordinator(
            preferences: store,
            helperLauncher: launcher,
            loginItemManager: StatefulLoginItem(status: .disabled)
        )

        _ = try coordinator.save(.defaults)

        XCTAssertEqual(launcher.launchCount, 1)
    }

    func testPermissionPaneRoutingPrioritizesAccessibility() {
        let coordinator = SettingsCoordinator(
            preferences: InMemoryPreferences(request: .init(settings: .defaults, applyRequestID: UUID())),
            helperLauncher: RecordingHelperLauncher(),
            loginItemManager: StatefulLoginItem(status: .disabled)
        )
        let requestID = UUID()
        let both = TidyTapApplyStatus(
            applyRequestID: requestID,
            outcome: .partiallyApplied,
            failedComponent: .eventTap,
            errorCode: "eventTap.permissionPartial.accessibility.inputMonitoring"
        )
        let inputOnly = TidyTapApplyStatus(
            applyRequestID: requestID,
            outcome: .partiallyApplied,
            failedComponent: .eventTap,
            errorCode: "eventTap.permissionPartial.inputMonitoring"
        )

        XCTAssertEqual(coordinator.permissionSettingsPane(for: both), .accessibility)
        XCTAssertEqual(coordinator.permissionSettingsPane(for: inputOnly), .inputMonitoring)
    }

    func testRuntimePermissionLossNormalizesAllOffTapBeforeHelperCleanup() {
        let requestID = UUID()
        var settings = TidyTapSettings.defaults
        settings.sideButtonNavigation = true
        let store = InMemoryPreferences(request: .init(settings: settings, applyRequestID: requestID))
        let permissions = MutableInputPermissions(accessibility: true, inputMonitoring: true)
        let backend = FakeEventTapBackend()
        let input = InputFeaturesAdapter(
            permissionChecker: permissions,
            backend: backend,
            sideButtons: SideButtonController(
                applicationProvider: FakeFocusedProvider(),
                synthesizer: FakeNavigationSynthesizer()
            )
        )
        let terminator = RecordingTerminator(calls: CallLog())
        let coordinator = ApplyCoordinator(
            preferences: store,
            capsFeature: RecordingCaps(calls: CallLog()),
            inputFeatures: input,
            menuBar: RecordingMenu(calls: CallLog()),
            terminator: terminator
        )
        _ = coordinator.applyLatestSettings()
        var runtime: (UUID, TidyTapInputFeatureApplyResult?, TidyTapInputFeatureAdapterError?)?
        input.runtimeStatusHandler = { runtime = ($0, $1, $2) }
        permissions.accessibilityAllowed = false

        XCTAssertEqual(backend.send(.buttonDown(3)), .passThrough)
        let update = runtime
        XCTAssertNotNil(update)
        coordinator.reportRuntimeInput(requestID: update!.0, update!.1, error: update!.2)

        XCTAssertEqual(input.currentConfiguration(), .disabled)
        XCTAssertNil(backend.handler)
        XCTAssertFalse(store.request.settings.sideButtonNavigation)
        XCTAssertEqual(terminator.calls.values, ["terminate"])
    }

    private func makeCapsController(system: FakeCapsSystem) -> CapsLockFeatureController {
        CapsLockFeatureController(
            hid: CapsLockController(system: system),
            hotkey: InputSourceShortcutController(system: system),
            inputSources: system
        )
    }

    private func makeCapsAdapter(
        system: FakeCapsSystem,
        ownership: InMemoryCapsOwnership
    ) -> CapsLockFeatureAdapter {
        CapsLockFeatureAdapter(controller: makeCapsController(system: system), ownershipStore: ownership)
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
    var enabled: Bool
    init(calls: CallLog, enabled: Bool = false) { self.calls = calls; self.enabled = enabled }
    func apply(capsLockEnabled: Bool) throws { calls.values.append("caps:\(capsLockEnabled)"); enabled = capsLockEnabled }
    func currentCapsLockEnabled() throws -> Bool { enabled }
}

private final class RecordingInput: TidyTapInputFeaturesApplying {
    let calls: CallLog
    var configuration: TidyTapInputFeatureConfiguration
    init(calls: CallLog, configuration: TidyTapInputFeatureConfiguration = .disabled) {
        self.calls = calls; self.configuration = configuration
    }
    func apply(reverseMouseWheel: Bool, sideButtonNavigation: Bool, requestID: UUID) throws -> TidyTapInputFeatureApplyResult {
        calls.values.append("input:\(reverseMouseWheel):\(sideButtonNavigation)")
        configuration = .init(reverseMouseWheel: reverseMouseWheel, sideButtonNavigation: sideButtonNavigation)
        return .applied
    }
    func forcePassThrough() throws { calls.values.append("input:passThrough"); configuration = .disabled }
    func currentConfiguration() -> TidyTapInputFeatureConfiguration { configuration }
}

private final class FailingInput: TidyTapInputFeaturesApplying {
    let calls: CallLog
    init(calls: CallLog) { self.calls = calls }
    var configuration: TidyTapInputFeatureConfiguration = .disabled
    func apply(reverseMouseWheel: Bool, sideButtonNavigation: Bool, requestID: UUID) throws -> TidyTapInputFeatureApplyResult {
        calls.values.append("input:\(reverseMouseWheel):\(sideButtonNavigation)")
        if reverseMouseWheel {
            throw TestError.failure
        }
        configuration = .init(reverseMouseWheel: reverseMouseWheel, sideButtonNavigation: sideButtonNavigation)
        return .applied
    }
    func forcePassThrough() throws { calls.values.append("input:passThrough"); configuration = .disabled }
    func currentConfiguration() -> TidyTapInputFeatureConfiguration { configuration }
}

private final class FailingRollbackInput: TidyTapInputFeaturesApplying {
    let calls: CallLog
    init(calls: CallLog) { self.calls = calls }
    var configuration: TidyTapInputFeatureConfiguration = .disabled
    func apply(reverseMouseWheel: Bool, sideButtonNavigation: Bool, requestID: UUID) throws -> TidyTapInputFeatureApplyResult {
        calls.values.append("input:\(reverseMouseWheel):\(sideButtonNavigation)")
        if !reverseMouseWheel {
            throw TestError.failure
        }
        configuration = .init(reverseMouseWheel: reverseMouseWheel, sideButtonNavigation: sideButtonNavigation)
        return .applied
    }
    func forcePassThrough() throws { calls.values.append("input:passThrough"); configuration = .disabled }
    func currentConfiguration() -> TidyTapInputFeatureConfiguration { configuration }
}

private final class PartialInput: TidyTapInputFeaturesApplying {
    var configuration: TidyTapInputFeatureConfiguration = .disabled
    func apply(reverseMouseWheel: Bool, sideButtonNavigation: Bool, requestID: UUID) throws -> TidyTapInputFeatureApplyResult {
        configuration = .init(reverseMouseWheel: false, sideButtonNavigation: sideButtonNavigation)
        return .partiallyApplied(unavailablePermissions: [.inputMonitoring])
    }
    func forcePassThrough() throws {}
    func currentConfiguration() -> TidyTapInputFeatureConfiguration { configuration }
}

private struct FakeInputPermissions: InputPermissionChecking {
    let accessibilityAllowed: Bool
    let inputMonitoringAllowed: Bool
    init(accessibility: Bool, inputMonitoring: Bool) {
        accessibilityAllowed = accessibility
        inputMonitoringAllowed = inputMonitoring
    }
}

private final class MutableInputPermissions: InputPermissionChecking, @unchecked Sendable {
    var accessibilityAllowed: Bool
    var inputMonitoringAllowed: Bool
    init(accessibility: Bool, inputMonitoring: Bool) {
        accessibilityAllowed = accessibility
        inputMonitoringAllowed = inputMonitoring
    }
}

private final class FakeEventTapBackend: EventTapBackend, @unchecked Sendable {
    var configurations = [EventTapConfiguration]()
    var captureSideButtons = [Bool]()
    var handler: EventTapHandler?
    var synchronousInputOnInstall: EventTapInput?
    func install(configuration: EventTapConfiguration, captureSideButtons: Bool, handler: @escaping EventTapHandler) throws {
        configurations.append(configuration)
        self.captureSideButtons.append(captureSideButtons)
        self.handler = handler
        if let synchronousInputOnInstall {
            self.synchronousInputOnInstall = nil
            _ = handler(synchronousInputOnInstall)
        }
    }
    func enable() throws {}
    func uninstall() { handler = nil }
    func send(_ input: EventTapInput) -> EventTapOutput { handler?(input) ?? .passThrough }
}

private struct FakeFocusedProvider: FocusedApplicationProviding {
    func focusedApplication() -> FocusedApplication? { nil }
}

private struct FakeNavigationSynthesizer: NavigationSynthesizing {
    func synthesize(_ direction: NavigationDirection, for target: FocusedApplication) -> Bool { false }
}

private final class InMemoryCapsOwnership: TidyTapCapsOwnershipStoring {
    var data: Data?
    func readCapsLockJournalData() -> Data? { data }
    func writeCapsLockJournalData(_ data: Data?) throws { self.data = data }
}

private final class FakeCapsSystem: HIDMappingApplying, SymbolicHotkeyApplying, InputSourceCounting, @unchecked Sendable {
    var mappings = [HIDMapping]()
    var domain = PropertyListDictionary()
    var activationCount = 0
    func readHIDMappings() throws -> [HIDMapping] { mappings }
    func applyHIDMappings(_ mappings: [HIDMapping]) throws { self.mappings = mappings }
    func readSymbolicHotkeyDomain() throws -> PropertyListDictionary { domain }
    func applySymbolicHotkeyDomain(_ domain: PropertyListDictionary) throws { self.domain = domain }
    func activateSymbolicHotkeySettings() throws { activationCount += 1 }
    func enabledSelectableInputSourceCount() throws -> Int { 2 }
}

private final class RecordingMenu: TidyTapMenuBarApplying {
    let calls: CallLog
    var isMenuBarVisible: Bool
    init(calls: CallLog, visible: Bool = false) { self.calls = calls; isMenuBarVisible = visible }
    func applyMenuBar(visible: Bool) throws { calls.values.append("menu:\(visible)"); isMenuBarVisible = visible }
}

private final class FailingMenu: TidyTapMenuBarApplying {
    let calls: CallLog
    let failWhenVisible: Bool
    let failWhenHidden: Bool
    var isMenuBarVisible = false

    init(
        calls: CallLog,
        failWhenVisible: Bool,
        failWhenHidden: Bool,
        initiallyVisible: Bool = false
    ) {
        self.calls = calls
        self.failWhenVisible = failWhenVisible
        self.failWhenHidden = failWhenHidden
        isMenuBarVisible = initiallyVisible
    }

    func applyMenuBar(visible: Bool) throws {
        calls.values.append("menu:\(visible)")
        if visible ? failWhenVisible : failWhenHidden {
            throw TestError.failure
        }
        isMenuBarVisible = visible
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

private final class StatefulLoginItem: TidyTapLoginItemManaging {
    var liveStatus: TidyTapLoginItemStatus

    init(status: TidyTapLoginItemStatus) {
        liveStatus = status
    }

    func setEnabled(_ enabled: Bool) throws {
        if !enabled { liveStatus = .disabled }
    }

    func status() -> TidyTapLoginItemStatus { liveStatus }
}

private final class ThrowingCaps: TidyTapCapsFeatureApplying {
    let error: Error
    init(error: Error) { self.error = error }
    func apply(capsLockEnabled: Bool) throws { throw error }
    func currentCapsLockEnabled() throws -> Bool { false }
}

private enum TestError: Error, Equatable {
    case failure
    case persistence
    case recovery
}
