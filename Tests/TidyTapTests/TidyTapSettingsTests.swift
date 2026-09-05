import XCTest
import TidyTapInputEngine

@MainActor
final class TidyTapSettingsTests: XCTestCase {
    func testLaunchSmokeRequiresFlagAndScopedPreferencesSuite() {
        let suite = "\(TidyTapLaunchSmoke.suitePrefix)UnitTest"

        XCTAssertNil(TidyTapLaunchSmoke.current(environment: [:]))
        XCTAssertNil(TidyTapLaunchSmoke.current(environment: [
            TidyTapLaunchSmoke.enabledKey: "1",
            TidyTapLaunchSmoke.preferencesSuiteKey: TidyTapPreferences.domain
        ]))
        XCTAssertEqual(
            TidyTapLaunchSmoke.current(environment: [
                TidyTapLaunchSmoke.enabledKey: "1",
                TidyTapLaunchSmoke.preferencesSuiteKey: suite
            ])?.preferencesSuite,
            suite
        )
    }

    func testDefaultSettingsKeepEveryCapabilityDisabled() {
        XCTAssertEqual(TidyTapSettings.defaults, TidyTapSettings(
            capsLockInputSourceSwitching: false,
            reverseMouseWheelVertically: false,
            sideButtonNavigation: false,
            launchAtLogin: false
        ))
    }

    func testBundleIdentifiersUseTheTidyTapNamespace() {
        XCTAssertEqual(TidyTapProduct.appBundleIdentifier, "com.sharknia.TidyTap")
        XCTAssertEqual(TidyTapProduct.helperBundleIdentifier, "com.sharknia.TidyTap.Helper")
    }

    func testPermissionSettingsURLsTargetTheirExactPrivacyPanes() {
        XCTAssertEqual(
            SettingsCoordinator.permissionSettingsURL(for: .accessibility).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
        XCTAssertEqual(
            SettingsCoordinator.permissionSettingsURL(for: .inputMonitoring).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
    }

    func testOnlyCoreFeaturesKeepHelperAlive() {
        XCTAssertFalse(TidyTapSettings.defaults.requiresHelper)

        var settings = TidyTapSettings.defaults
        settings.launchAtLogin = true
        XCTAssertFalse(settings.requiresHelper)

        settings.sideButtonNavigation = true
        XCTAssertTrue(settings.requiresHelper)
    }

    func testLegacyMenuBarPreferenceIsIgnoredWhenDecoded() throws {
        let data = Data("""
        {"capsLockInputSourceSwitching":false,"reverseMouseWheelVertically":false,"sideButtonNavigation":false,"launchAtLogin":false,"showInMenuBar":true}
        """.utf8)

        let settings = try JSONDecoder().decode(TidyTapSettings.self, from: data)

        XCTAssertEqual(settings, .defaults)
        XCTAssertFalse(settings.requiresHelper)
        XCTAssertFalse(String(data: try JSONEncoder().encode(settings), encoding: .utf8)!.contains("showInMenuBar"))
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
                launchAtLogin: false
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

    func testRollbackReportsEveryComponentThatCouldNotBeRestored() {
        let requestID = UUID()
        let store = InMemoryPreferences(request: TidyTapSettingsRequest(
            settings: enabledSettings(),
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
            launchAtLogin: false
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
            launchAtLogin: true
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
            launchAtLogin: false
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

    func testUnknownCapsOwnershipVersionIsReportedAsCapsConflict() throws {
        let system = FakeCapsSystem()
        system.mappings = [.tidyTapCapsLock]
        system.domain = InputSourceShortcutController.replacingHotkey60(
            in: [:],
            with: .tidyTapHotkey60
        )
        let ownership = InMemoryCapsOwnership(data: try JSONEncoder().encode(CapsJournal(
            enabled: true,
            phase: .applied,
            ownership: CapsLockFeatureOwnership(
                hid: CapsHIDOwnership(version: 99),
                hotkey60: Hotkey60Ownership(backup: nil)
            )
        )))
        var settings = TidyTapSettings.defaults
        settings.capsLockInputSourceSwitching = true
        let coordinator = ApplyCoordinator(
            preferences: InMemoryPreferences(request: .init(settings: settings, applyRequestID: UUID())),
            capsFeature: makeCapsAdapter(system: system, ownership: ownership),
            inputFeatures: RecordingInput(calls: CallLog()),
            menuBar: RecordingMenu(calls: CallLog()),
            terminator: RecordingTerminator(calls: CallLog())
        )

        let status = coordinator.applyLatestSettings()

        XCTAssertEqual(status.failedComponent, .capsLock)
        XCTAssertEqual(status.errorCode, "capsLock.conflict.hidOwnership")
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
            launchAtLogin: false
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
            launchAtLogin: false
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
        newer.launchAtLogin = true
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
            (InputEngineError.preWriteStateChanged(.hidMappings), "capsLock.preWriteStateChanged.hidMappings"),
            (InputEngineError.staleSystemState(.hidMappings), "capsLock.recoveryRequired.hidMappings"),
            (InputEngineError.verificationFailed(.symbolicHotkey60), "capsLock.verificationFailed.symbolicHotkey60"),
            (InputEngineError.invalidSystemData(.symbolicHotkey60), "capsLock.invalidSystemData.symbolicHotkey60"),
            (InputEngineError.commandFailed(
                executable: "/secret/tool",
                status: 127,
                detail: "private stderr"
            ), "capsLock.commandFailed"),
            (InputEngineError.eventTapCreationFailed, "capsLock.creationFailed"),
            (InputEngineError.eventTapRecoveryFailed, "capsLock.recoveryFailed"),
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
            let code = coordinator.applyLatestSettings().errorCode
            XCTAssertEqual(code, expectedCode)
            XCTAssertFalse(code?.contains("secret") == true)
            XCTAssertFalse(code?.contains("private stderr") == true)
            XCTAssertLessThanOrEqual(code?.count ?? 0, 96)
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

    func testConfirmedPermissionRefreshAdvancesFromAccessibilityToInputMonitoring() {
        let coordinator = SettingsCoordinator(
            preferences: InMemoryPreferences(request: .init(settings: .defaults, applyRequestID: UUID())),
            helperLauncher: RecordingHelperLauncher(),
            loginItemManager: StatefulLoginItem(status: .disabled)
        )
        let status = TidyTapApplyStatus(
            applyRequestID: UUID(),
            outcome: .partiallyApplied,
            failedComponent: .eventTap,
            errorCode: "eventTap.permissionPartial.accessibility.inputMonitoring"
        )

        XCTAssertEqual(
            coordinator.permissionSettingsPane(
                for: status,
                confirmed: .init(accessibility: .denied, inputMonitoring: .denied)
            ),
            .accessibility
        )
        XCTAssertEqual(
            coordinator.permissionSettingsPane(
                for: status,
                confirmed: .init(accessibility: .authorized, inputMonitoring: .denied)
            ),
            .inputMonitoring
        )
        XCTAssertNil(coordinator.permissionSettingsPane(
            for: status,
            confirmed: .init(accessibility: .authorized, inputMonitoring: .authorized)
        ))
    }

    func testForegroundRefreshUsesCorrelatedResultWithoutChangingFeatureState() throws {
        let applyID = UUID()
        var sanitized = TidyTapSettings.defaults
        sanitized.capsLockInputSourceSwitching = true
        let store = InMemoryPreferences(request: .init(settings: sanitized, applyRequestID: applyID))
        store.status = TidyTapApplyStatus(
            applyRequestID: applyID,
            outcome: .partiallyApplied,
            failedComponent: .eventTap,
            errorCode: "eventTap.permissionPartial.accessibility",
            effectiveSettings: sanitized
        )
        let launcher = RecordingHelperLauncher()
        let coordinator = SettingsCoordinator(
            preferences: store,
            helperLauncher: launcher,
            loginItemManager: StatefulLoginItem(status: .disabled)
        )
        coordinator.restoreSession()
        let requestID = try XCTUnwrap(coordinator.latestPermissionRequestID)

        XCTAssertEqual(store.permissionRequest, .init(requestID: requestID, kind: .refresh, permission: nil))
        XCTAssertEqual(store.request.settings, sanitized)
        XCTAssertEqual(store.status?.applyRequestID, applyID)

        store.permissionResult = .init(
            requestID: UUID(),
            state: .init(accessibility: .authorized, inputMonitoring: .authorized)
        )
        XCTAssertNil(coordinator.receivePermissionResult(), "a stale helper response must not clear the notice")
        XCTAssertEqual(coordinator.latestPermissionRequestID, requestID)

        let current = TidyTapPermissionResult(
            requestID: requestID,
            state: .init(accessibility: .authorized, inputMonitoring: .denied)
        )
        store.permissionResult = current
        XCTAssertEqual(coordinator.receivePermissionResult(), current)
        XCTAssertNil(coordinator.latestPermissionRequestID)
        XCTAssertEqual(store.request.settings, sanitized)
        XCTAssertEqual(store.status?.applyRequestID, applyID)
        XCTAssertEqual(launcher.launchCount, 1, "startup persists refresh before launching the helper")

        XCTAssertNotNil(try coordinator.refreshPermissionsIfNeeded(), "a later foreground return requests a fresh check")
        XCTAssertEqual(store.request.settings, sanitized)
        XCTAssertEqual(launcher.launchCount, 2)
    }

    func testHelperExplicitRequestPromptsDeniedPermissionOnceThenReportsGranted() {
        let store = InMemoryPreferences(request: .init(settings: .defaults, applyRequestID: UUID()))
        let request = TidyTapPermissionRequest(
            requestID: UUID(),
            kind: .request,
            permission: .accessibility
        )
        store.permissionRequest = request
        let provider = RecordingPermissionProvider(
            state: .init(accessibility: .denied, inputMonitoring: .denied),
            grantsOnRequest: [.accessibility]
        )
        let coordinator = HelperPermissionCoordinator(preferences: store, provider: provider)

        let result = coordinator.handleLatestRequest()
        _ = coordinator.handleLatestRequest()

        XCTAssertEqual(provider.requests, [.accessibility], "startup and DNC replay must not prompt twice")
        XCTAssertEqual(result?.requestID, request.requestID)
        XCTAssertEqual(result?.state.accessibility, .authorized)
        XCTAssertEqual(store.request.settings, .defaults)
        XCTAssertNil(store.status)
    }

    func testHelperDoesNotPromptWhenExplicitPermissionIsAlreadyGranted() {
        let store = InMemoryPreferences(request: .init(settings: .defaults, applyRequestID: UUID()))
        store.permissionRequest = .init(
            requestID: UUID(),
            kind: .request,
            permission: .inputMonitoring
        )
        let provider = RecordingPermissionProvider(
            state: .init(accessibility: .authorized, inputMonitoring: .authorized)
        )

        _ = HelperPermissionCoordinator(preferences: store, provider: provider).handleLatestRequest()

        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testHelperExplicitInputMonitoringRequestUsesInputMonitoringProviderPath() {
        let store = InMemoryPreferences(request: .init(settings: .defaults, applyRequestID: UUID()))
        store.permissionRequest = .init(
            requestID: UUID(),
            kind: .request,
            permission: .inputMonitoring
        )
        let provider = RecordingPermissionProvider(
            state: .init(accessibility: .authorized, inputMonitoring: .denied)
        )

        _ = HelperPermissionCoordinator(preferences: store, provider: provider).handleLatestRequest()

        XCTAssertEqual(provider.requests, [.inputMonitoring])
        XCTAssertEqual(store.permissionResult?.state.inputMonitoring, .denied)
    }

    func testReadOnlyRefreshNeverRequestsOrMutatesSanitizedSettings() {
        var sanitized = TidyTapSettings.defaults
        sanitized.capsLockInputSourceSwitching = true
        let applyID = UUID()
        let store = InMemoryPreferences(request: .init(settings: sanitized, applyRequestID: applyID))
        store.permissionRequest = .init(requestID: UUID(), kind: .refresh, permission: nil)
        let provider = RecordingPermissionProvider(
            state: .init(accessibility: .authorized, inputMonitoring: .denied)
        )

        let result = HelperPermissionCoordinator(preferences: store, provider: provider).handleLatestRequest()

        XCTAssertEqual(result?.state, provider.state)
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertEqual(store.request, .init(settings: sanitized, applyRequestID: applyID))
        XCTAssertNil(store.status)
    }

    func testCapsOnlyHelperStartupDoesNotCheckOrRequestPermissions() {
        var settings = TidyTapSettings.defaults
        settings.capsLockInputSourceSwitching = true
        let store = InMemoryPreferences(request: .init(settings: settings, applyRequestID: UUID()))
        let calls = CallLog()
        let provider = RecordingPermissionProvider(
            state: .init(accessibility: .denied, inputMonitoring: .denied)
        )
        let apply = ApplyCoordinator(
            preferences: store,
            capsFeature: RecordingCaps(calls: calls),
            inputFeatures: RecordingInput(calls: calls),
            menuBar: RecordingMenu(calls: calls),
            terminator: RecordingTerminator(calls: calls)
        )
        let lifecycle = HelperLifecycle(
            coordinator: apply,
            permissionCoordinator: HelperPermissionCoordinator(preferences: store, provider: provider)
        )

        lifecycle.start()
        lifecycle.stop()

        XCTAssertEqual(provider.checkCount, 0)
        XCTAssertTrue(provider.requests.isEmpty)
        XCTAssertEqual(calls.values.prefix(2), ["caps:true", "input:false:false"])
    }

    func testHelperStartupDrainsPersistedRefreshWhenLaunchNotificationWasMissed() {
        let store = InMemoryPreferences(request: .init(settings: .defaults, applyRequestID: UUID()))
        let permissionID = UUID()
        store.permissionRequest = .init(requestID: permissionID, kind: .refresh, permission: nil)
        let provider = RecordingPermissionProvider(
            state: .init(accessibility: .authorized, inputMonitoring: .denied)
        )
        let calls = CallLog()
        let lifecycle = HelperLifecycle(
            coordinator: ApplyCoordinator(
                preferences: store,
                capsFeature: RecordingCaps(calls: calls),
                inputFeatures: RecordingInput(calls: calls),
                menuBar: RecordingMenu(calls: calls),
                terminator: RecordingTerminator(calls: calls)
            ),
            permissionCoordinator: HelperPermissionCoordinator(preferences: store, provider: provider)
        )

        lifecycle.start()
        lifecycle.stop()

        XCTAssertEqual(store.permissionResult?.requestID, permissionID)
        XCTAssertEqual(store.permissionResult?.state.inputMonitoring, .denied)
        XCTAssertEqual(provider.checkCount, 1)
        XCTAssertTrue(provider.requests.isEmpty)
    }

    func testColdHelperKeepsInputMonitoringNoticeAfterAllOffStartupApply() throws {
        let applyID = UUID()
        let store = InMemoryPreferences(request: .init(settings: .defaults, applyRequestID: applyID))
        store.status = TidyTapApplyStatus(
            applyRequestID: applyID,
            outcome: .partiallyApplied,
            failedComponent: .eventTap,
            errorCode: "eventTap.permissionPartial.accessibility.inputMonitoring",
            effectiveSettings: .defaults
        )
        let app = SettingsCoordinator(
            preferences: store,
            helperLauncher: RecordingHelperLauncher(),
            loginItemManager: StatefulLoginItem(status: .disabled)
        )
        app.restoreSession()
        let permissionID = try XCTUnwrap(app.latestPermissionRequestID)
        let provider = RecordingPermissionProvider(
            state: .init(accessibility: .authorized, inputMonitoring: .denied)
        )
        let calls = CallLog()
        let lifecycle = HelperLifecycle(
            coordinator: ApplyCoordinator(
                preferences: store,
                capsFeature: RecordingCaps(calls: calls),
                inputFeatures: RecordingInput(calls: calls),
                menuBar: RecordingMenu(calls: calls),
                terminator: RecordingTerminator(calls: calls)
            ),
            permissionCoordinator: HelperPermissionCoordinator(preferences: store, provider: provider)
        )

        lifecycle.start()
        lifecycle.stop()

        XCTAssertEqual(store.permissionResults.map(\.requestID), [permissionID])
        XCTAssertEqual(store.applyStatuses.map(\.outcome), [.applied, .partiallyApplied])
        let permissionNotificationResult = app.receivePermissionResult()
        let applyNotificationResult = app.receiveApplyResult()
        XCTAssertEqual(permissionNotificationResult?.state, provider.state)
        XCTAssertEqual(applyNotificationResult?.errorCode, "eventTap.permissionPartial.inputMonitoring")
        XCTAssertEqual(
            app.permissionSettingsPane(
                for: try XCTUnwrap(applyNotificationResult),
                confirmed: try XCTUnwrap(permissionNotificationResult).state
            ),
            .inputMonitoring
        )
        XCTAssertEqual(store.request.settings, .defaults)
    }

    func testColdHelperKeepsInputMonitoringNoticeWhenSideButtonsRemainApplied() throws {
        let applyID = UUID()
        var sanitized = TidyTapSettings.defaults
        sanitized.sideButtonNavigation = true
        let store = InMemoryPreferences(request: .init(settings: sanitized, applyRequestID: applyID))
        store.status = TidyTapApplyStatus(
            applyRequestID: applyID,
            outcome: .partiallyApplied,
            failedComponent: .eventTap,
            errorCode: "eventTap.permissionPartial.inputMonitoring",
            effectiveSettings: sanitized
        )
        store.permissionRequest = .init(requestID: UUID(), kind: .refresh, permission: nil)
        let provider = RecordingPermissionProvider(
            state: .init(accessibility: .authorized, inputMonitoring: .denied)
        )
        let calls = CallLog()
        let lifecycle = HelperLifecycle(
            coordinator: ApplyCoordinator(
                preferences: store,
                capsFeature: RecordingCaps(calls: calls),
                inputFeatures: RecordingInput(calls: calls),
                menuBar: RecordingMenu(calls: calls),
                terminator: RecordingTerminator(calls: calls)
            ),
            permissionCoordinator: HelperPermissionCoordinator(preferences: store, provider: provider)
        )
        lifecycle.start()
        lifecycle.stop()

        XCTAssertEqual(store.applyStatuses.map(\.outcome), [.applied, .partiallyApplied])
        let final = try XCTUnwrap(store.status)
        XCTAssertEqual(final.errorCode, "eventTap.permissionPartial.inputMonitoring")
        XCTAssertEqual(final.effectiveSettings, sanitized)
        XCTAssertEqual(calls.values.prefix(2), ["caps:false", "input:false:true"])
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

    func testEnableFinalJournalWriteFailureRollsBackAppliedCapsState() {
        let requestID = UUID()
        var settings = TidyTapSettings.defaults
        settings.capsLockInputSourceSwitching = true
        let preferences = InMemoryPreferences(request: .init(settings: settings, applyRequestID: requestID))
        let system = FakeCapsSystem()
        let ownership = InMemoryCapsOwnership(failingWriteNumbers: [2])
        let coordinator = ApplyCoordinator(
            preferences: preferences,
            capsFeature: makeCapsAdapter(system: system, ownership: ownership),
            inputFeatures: RecordingInput(calls: CallLog()),
            menuBar: RecordingMenu(calls: CallLog()),
            terminator: RecordingTerminator(calls: CallLog())
        )

        let status = coordinator.applyLatestSettings()

        XCTAssertEqual(status.outcome, .failed)
        XCTAssertEqual(status.effectiveSettings?.capsLockInputSourceSwitching, false)
        XCTAssertTrue(system.mappings.isEmpty)
        XCTAssertNil(InputSourceShortcutController.hotkey60(in: system.domain))
        XCTAssertNil(ownership.data)
    }

    func testDisableFinalJournalClearFailureRestoresExactOwnedCapsState() throws {
        let system = FakeCapsSystem()
        let ownership = InMemoryCapsOwnership()
        let adapter = makeCapsAdapter(system: system, ownership: ownership)
        try adapter.apply(capsLockEnabled: true)
        ownership.failingWriteNumbers = [4]
        let requestID = UUID()
        let preferences = InMemoryPreferences(request: .init(settings: .defaults, applyRequestID: requestID))
        let coordinator = ApplyCoordinator(
            preferences: preferences,
            capsFeature: adapter,
            inputFeatures: RecordingInput(calls: CallLog()),
            menuBar: RecordingMenu(calls: CallLog()),
            terminator: RecordingTerminator(calls: CallLog())
        )

        let status = coordinator.applyLatestSettings()

        XCTAssertEqual(status.outcome, .failed)
        XCTAssertEqual(status.effectiveSettings?.capsLockInputSourceSwitching, true)
        XCTAssertEqual(system.mappings, [.tidyTapCapsLock])
        XCTAssertEqual(InputSourceShortcutController.hotkey60(in: system.domain), .tidyTapHotkey60)
        XCTAssertTrue(try adapter.currentCapsLockEnabled())
    }

    func testRuntimeReenableFailurePersistsActualStoppedConfiguration() {
        let requestID = UUID()
        var settings = TidyTapSettings.defaults
        settings.reverseMouseWheelVertically = true
        let preferences = InMemoryPreferences(request: .init(settings: settings, applyRequestID: requestID))
        let backend = FakeEventTapBackend()
        let input = InputFeaturesAdapter(
            permissionChecker: MutableInputPermissions(accessibility: true, inputMonitoring: true),
            backend: backend,
            sideButtons: SideButtonController(
                applicationProvider: FakeFocusedProvider(),
                synthesizer: FakeNavigationSynthesizer()
            )
        )
        let coordinator = ApplyCoordinator(
            preferences: preferences,
            capsFeature: RecordingCaps(calls: CallLog()),
            inputFeatures: input,
            menuBar: RecordingMenu(calls: CallLog()),
            terminator: RecordingTerminator(calls: CallLog())
        )
        _ = coordinator.applyLatestSettings()
        var runtime: (UUID, TidyTapInputFeatureApplyResult?, TidyTapInputFeatureAdapterError?)?
        input.runtimeStatusHandler = { runtime = ($0, $1, $2) }
        backend.enableError = TestError.failure

        XCTAssertEqual(backend.send(.disabled(.timeout)), .passThrough)
        let update = runtime
        XCTAssertNotNil(update)
        coordinator.reportRuntimeInput(requestID: update!.0, update!.1, error: update!.2)

        XCTAssertEqual(preferences.status?.outcome, .failed)
        XCTAssertEqual(preferences.status?.errorCode, "eventTap.recoveryFailed")
        XCTAssertEqual(preferences.status?.effectiveSettings?.reverseMouseWheelVertically, false)
        XCTAssertFalse(preferences.request.settings.reverseMouseWheelVertically)
        XCTAssertEqual(input.currentConfiguration(), .disabled)
        XCTAssertNil(backend.handler)
    }

    func testInnerTransactionRecoveryRequiredOutcomeIsPreserved() {
        let requestID = UUID()
        var settings = TidyTapSettings.defaults
        settings.capsLockInputSourceSwitching = true
        let transaction = TransactionFailure(
            primaryDescription: "private detail",
            rollbackIssues: [.init(component: .hidMappings, description: "private rollback detail")]
        )
        let coordinator = ApplyCoordinator(
            preferences: InMemoryPreferences(request: .init(settings: settings, applyRequestID: requestID)),
            capsFeature: ThrowingCaps(error: transaction),
            inputFeatures: RecordingInput(calls: CallLog()),
            menuBar: RecordingMenu(calls: CallLog()),
            terminator: RecordingTerminator(calls: CallLog())
        )

        let status = coordinator.applyLatestSettings()

        XCTAssertEqual(status.outcome, .recoveryRequired)
        XCTAssertEqual(status.errorCode, "capsLock.recoveryRequired.hidMappings")
        XCTAssertEqual(status.effectiveSettings?.capsLockInputSourceSwitching, false)
    }

    func testInnerRecoveryAndFailedOuterRestoreReportsActualRemainingCapsState() {
        let requestID = UUID()
        var settings = TidyTapSettings.defaults
        settings.capsLockInputSourceSwitching = true
        let caps = MutatingRecoveryCaps()
        let coordinator = ApplyCoordinator(
            preferences: InMemoryPreferences(request: .init(settings: settings, applyRequestID: requestID)),
            capsFeature: caps,
            inputFeatures: RecordingInput(calls: CallLog()),
            menuBar: RecordingMenu(calls: CallLog()),
            terminator: RecordingTerminator(calls: CallLog())
        )

        let status = coordinator.applyLatestSettings()

        XCTAssertEqual(status.outcome, .recoveryRequired)
        XCTAssertEqual(status.errorCode, "lifecycle.rollbackFailed.capsLock")
        XCTAssertEqual(status.effectiveSettings?.capsLockInputSourceSwitching, true)
        XCTAssertTrue(caps.enabled)
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

    private func enabledSettings() -> TidyTapSettings {
        TidyTapSettings(
            capsLockInputSourceSwitching: true,
            reverseMouseWheelVertically: true,
            sideButtonNavigation: false,
            launchAtLogin: false
        )
    }
}

private final class InMemoryPreferences: TidyTapPreferencesStoring {
    var request: TidyTapSettingsRequest
    var status: TidyTapApplyStatus?
    var permissionRequest: TidyTapPermissionRequest?
    var permissionResult: TidyTapPermissionResult?
    var applyStatuses = [TidyTapApplyStatus]()
    var permissionResults = [TidyTapPermissionResult]()
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
    func writeApplyStatus(_ status: TidyTapApplyStatus) throws {
        self.status = status
        applyStatuses.append(status)
    }
    func readPermissionRequest() -> TidyTapPermissionRequest? { permissionRequest }
    func writePermissionRequest(_ request: TidyTapPermissionRequest) throws {
        permissionRequest = request
    }
    func readPermissionResult() -> TidyTapPermissionResult? { permissionResult }
    func writePermissionResult(_ result: TidyTapPermissionResult) throws {
        permissionResult = result
        permissionResults.append(result)
    }
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

private final class RecordingPermissionProvider: TidyTapPermissionProviding {
    var state: TidyTapFeaturePermissionState
    var grantsOnRequest: Set<TidyTapPermission>
    private(set) var checkCount = 0
    private(set) var requests = [TidyTapPermission]()

    init(
        state: TidyTapFeaturePermissionState,
        grantsOnRequest: Set<TidyTapPermission> = []
    ) {
        self.state = state
        self.grantsOnRequest = grantsOnRequest
    }

    func currentState() -> TidyTapFeaturePermissionState {
        checkCount += 1
        return state
    }

    func request(_ permission: TidyTapPermission) {
        requests.append(permission)
        guard grantsOnRequest.contains(permission) else { return }
        switch permission {
        case .accessibility: state.accessibility = .authorized
        case .inputMonitoring: state.inputMonitoring = .authorized
        }
    }
}

private final class FakeEventTapBackend: EventTapBackend, @unchecked Sendable {
    var configurations = [EventTapConfiguration]()
    var captureSideButtons = [Bool]()
    var handler: EventTapHandler?
    var synchronousInputOnInstall: EventTapInput?
    var enableError: Error?
    func install(configuration: EventTapConfiguration, captureSideButtons: Bool, handler: @escaping EventTapHandler) throws {
        configurations.append(configuration)
        self.captureSideButtons.append(captureSideButtons)
        self.handler = handler
        if let synchronousInputOnInstall {
            self.synchronousInputOnInstall = nil
            _ = handler(synchronousInputOnInstall)
        }
    }
    func enable() throws {
        if let enableError { throw enableError }
    }
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
    var writeCount = 0
    var failingWriteNumbers: Set<Int>

    init(data: Data? = nil, failingWriteNumbers: Set<Int> = []) {
        self.data = data
        self.failingWriteNumbers = failingWriteNumbers
    }

    func readCapsLockJournalData() -> Data? { data }
    func writeCapsLockJournalData(_ data: Data?) throws {
        writeCount += 1
        if failingWriteNumbers.contains(writeCount) { throw TestError.persistence }
        self.data = data
    }
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
    private var enabled = false
    init(error: Error) { self.error = error }
    func apply(capsLockEnabled: Bool) throws {
        if capsLockEnabled { throw error }
        enabled = false
    }
    func currentCapsLockEnabled() throws -> Bool { enabled }
}

private final class MutatingRecoveryCaps: TidyTapCapsFeatureApplying {
    var enabled = false

    func apply(capsLockEnabled: Bool) throws {
        if capsLockEnabled {
            enabled = true
            throw TransactionFailure(
                primaryDescription: "private primary detail",
                rollbackIssues: [.init(component: .hidMappings, description: "private rollback detail")]
            )
        }
        throw TestError.recovery
    }

    func currentCapsLockEnabled() throws -> Bool { enabled }
}

private enum TestError: Error, Equatable {
    case failure
    case persistence
    case recovery
}
