import XCTest
@testable import TidyTapInputEngine

private final class FakePermissions: InputPermissionChecking, @unchecked Sendable {
    var accessibilityAllowed: Bool
    var inputMonitoringAllowed: Bool

    init(accessibility: Bool, inputMonitoring: Bool) {
        accessibilityAllowed = accessibility
        inputMonitoringAllowed = inputMonitoring
    }
}

private final class FakeEventTapBackend: EventTapBackend, @unchecked Sendable {
    var handler: EventTapHandler?
    var installedHandlers: [EventTapHandler] = []
    var installCount = 0
    var enableCount = 0
    var uninstallCount = 0
    var captureSideButtonsValues: [Bool] = []
    var installedConfigurations: [EventTapConfiguration] = []
    var installError: Error?
    var enableError: Error?

    func install(
        configuration: EventTapConfiguration,
        captureSideButtons: Bool,
        handler: @escaping EventTapHandler
    ) throws {
        installCount += 1
        captureSideButtonsValues.append(captureSideButtons)
        installedConfigurations.append(configuration)
        if let installError { throw installError }
        self.handler = handler
        installedHandlers.append(handler)
    }

    func enable() throws {
        enableCount += 1
        if let enableError { throw enableError }
    }

    func uninstall() {
        uninstallCount += 1
        handler = nil
    }

    func send(_ input: EventTapInput) -> EventTapOutput {
        handler?(input) ?? .passThrough
    }
}

final class EventTapControllerTests: XCTestCase {
    func testNoFeaturesStopsWithoutPermissionCheckOrInstall() {
        let (controller, _, backend, _) = makeController(accessibility: false, inputMonitoring: false)

        let status = controller.start(
            configuration: EventTapConfiguration(
                reverseMouseScroll: false,
                sideButtonNavigation: false
            )
        )

        XCTAssertEqual(status, .stopped)
        XCTAssertEqual(backend.installCount, 0)
        XCTAssertEqual(backend.uninstallCount, 1)
    }

    func testScrollRequiresBothPermissions() {
        let (controller, _, backend, _) = makeController(accessibility: true, inputMonitoring: false)
        let configuration = EventTapConfiguration(
            reverseMouseScroll: true,
            sideButtonNavigation: false
        )

        XCTAssertEqual(controller.start(configuration: configuration), .permissionDenied([.inputMonitoring]))
        XCTAssertEqual(backend.installCount, 0)
    }

    func testNavigationRequiresAccessibilityButNotInputMonitoring() {
        let (allowed, _, allowedBackend, _) = makeController(
            accessibility: true,
            inputMonitoring: false
        )
        let configuration = EventTapConfiguration(
            reverseMouseScroll: false,
            sideButtonNavigation: true
        )
        XCTAssertEqual(allowed.start(configuration: configuration), .running(configuration))
        XCTAssertEqual(allowedBackend.installCount, 1)

        let (denied, _, deniedBackend, _) = makeController(
            accessibility: false,
            inputMonitoring: true
        )
        XCTAssertEqual(denied.start(configuration: configuration), .permissionDenied([.accessibility]))
        XCTAssertEqual(deniedBackend.installCount, 0)
    }

    func testBackendInstallFailureBecomesStatus() {
        let (controller, _, backend, _) = makeController(accessibility: true, inputMonitoring: true)
        backend.installError = TestTapError.failure

        let status = controller.start(configuration: .init(
            reverseMouseScroll: true,
            sideButtonNavigation: false
        ))

        XCTAssertEqual(status, .failed(.eventTapCreationFailed))
    }

    func testRunningTapRoutesMouseScrollAndLeavesUnknownContinuousUnchanged() {
        let (controller, _, backend, _) = makeController(accessibility: true, inputMonitoring: true)
        _ = controller.start(configuration: .init(
            reverseMouseScroll: true,
            sideButtonNavigation: false
        ))
        let deltas = ScrollDeltaFields(
            verticalLine: 1,
            verticalPoint: 10,
            verticalFixed: 65_536,
            horizontalLine: 2,
            horizontalPoint: 20,
            horizontalFixed: 131_072
        )

        XCTAssertEqual(
            backend.send(.scroll(.init(
                timestampNanoseconds: 1,
                isContinuous: false,
                deltas: deltas,
                phase: [],
                momentumPhase: []
            ))),
            .replaceScrollDeltas(.init(
                verticalLine: -1,
                verticalPoint: -10,
                verticalFixed: -65_536,
                horizontalLine: 2,
                horizontalPoint: 20,
                horizontalFixed: 131_072
            ))
        )
        XCTAssertEqual(
            backend.send(.scroll(.init(
                timestampNanoseconds: 2,
                isContinuous: true,
                deltas: deltas,
                phase: [],
                momentumPhase: []
            ))),
            .passThrough
        )
    }

    func testDisabledTapReenablesWhenPermissionsRemainAvailable() {
        let (controller, _, backend, _) = makeController(accessibility: true, inputMonitoring: true)
        let configuration = EventTapConfiguration(
            reverseMouseScroll: true,
            sideButtonNavigation: true
        )
        _ = controller.start(configuration: configuration)

        XCTAssertEqual(backend.send(.disabled(.timeout)), .passThrough)
        XCTAssertEqual(backend.enableCount, 1)
        XCTAssertEqual(controller.status, .running(configuration))
    }

    func testDisabledTapDoesNotReenableAfterPermissionRevocation() {
        let (controller, permissions, backend, _) = makeController(
            accessibility: true,
            inputMonitoring: true
        )
        _ = controller.start(configuration: .init(
            reverseMouseScroll: true,
            sideButtonNavigation: false
        ))
        permissions.inputMonitoringAllowed = false

        XCTAssertEqual(backend.send(.disabled(.userInput)), .passThrough)
        XCTAssertEqual(backend.enableCount, 0)
        XCTAssertEqual(controller.status, .permissionDenied([.inputMonitoring]))
    }

    func testRevokedInputMonitoringPassesNextScrollWithoutMutation() {
        let (controller, permissions, backend, _) = makeController(
            accessibility: true,
            inputMonitoring: true
        )
        _ = controller.start(configuration: .init(
            reverseMouseScroll: true,
            sideButtonNavigation: false
        ))
        permissions.inputMonitoringAllowed = false
        let observation = ScrollObservation(
            timestampNanoseconds: 1,
            isContinuous: false,
            deltas: .init(
                verticalLine: 1,
                verticalPoint: 10,
                verticalFixed: 65_536,
                horizontalLine: 0,
                horizontalPoint: 0,
                horizontalFixed: 0
            ),
            phase: [],
            momentumPhase: []
        )

        XCTAssertEqual(backend.send(.scroll(observation)), .passThrough)
        XCTAssertEqual(controller.status, .permissionDenied([.inputMonitoring]))
    }

    func testGestureObservedWhileRevokedCannotAffectLaterScrollClassification() {
        let (controller, permissions, backend, _) = makeController(
            accessibility: true,
            inputMonitoring: true
        )
        _ = controller.start(configuration: .init(
            reverseMouseScroll: true,
            sideButtonNavigation: false
        ))
        permissions.inputMonitoringAllowed = false
        XCTAssertEqual(backend.send(.gesture(timestampNanoseconds: 1_000)), .passThrough)
        permissions.inputMonitoringAllowed = true

        XCTAssertEqual(
            backend.send(.scroll(.init(
                timestampNanoseconds: 1_050,
                isContinuous: true,
                deltas: .init(
                    verticalLine: 1,
                    verticalPoint: 2,
                    verticalFixed: 3,
                    horizontalLine: 0,
                    horizontalPoint: 0,
                    horizontalFixed: 0
                ),
                phase: [],
                momentumPhase: []
            ))),
            .passThrough,
            "the revoked gesture must not turn an unknown continuous event into trackpad state"
        )
    }

    func testRevokedAccessibilityPassesNextButtonWithoutSynthesis() {
        let (controller, permissions, backend, synthesizer) = makeController(
            accessibility: true,
            inputMonitoring: false
        )
        _ = controller.start(configuration: .init(
            reverseMouseScroll: false,
            sideButtonNavigation: true
        ))
        permissions.accessibilityAllowed = false

        XCTAssertEqual(backend.send(.buttonDown(3)), .passThrough)
        XCTAssertEqual(backend.send(.buttonUp(3)), .passThrough)
        XCTAssertEqual(synthesizer.directions, [])
        XCTAssertEqual(controller.status, .permissionDenied([.accessibility]))
    }

    func testRevocationDuringOwnedPressPassesRepeatAndUpAndDropsOwnership() {
        let (controller, permissions, backend, synthesizer) = makeController(
            accessibility: true,
            inputMonitoring: false
        )
        let configuration = EventTapConfiguration(
            reverseMouseScroll: false,
            sideButtonNavigation: true
        )
        _ = controller.start(configuration: configuration)
        XCTAssertEqual(backend.send(.buttonDown(3)), .consume)
        permissions.accessibilityAllowed = false

        XCTAssertEqual(backend.send(.buttonDown(3)), .passThrough)
        XCTAssertEqual(backend.send(.buttonUp(3)), .passThrough)
        XCTAssertEqual(synthesizer.directions, [.back])
        XCTAssertFalse(controller.status == .running(configuration))
    }

    func testRecoveryFailureIsReported() {
        let (controller, _, backend, _) = makeController(accessibility: true, inputMonitoring: true)
        _ = controller.start(configuration: .init(
            reverseMouseScroll: false,
            sideButtonNavigation: true
        ))
        backend.enableError = TestTapError.failure

        XCTAssertEqual(backend.send(.disabled(.timeout)), .passThrough)
        XCTAssertEqual(controller.status, .failed(.eventTapRecoveryFailed))
    }

    func testCombinedTapRecoversSideButtonsWhenInputMonitoringIsRevoked() {
        let (controller, permissions, backend, synthesizer) = makeController(
            accessibility: true,
            inputMonitoring: true
        )
        let combined = EventTapConfiguration(
            reverseMouseScroll: true,
            sideButtonNavigation: true
        )
        _ = controller.start(configuration: combined)
        XCTAssertEqual(backend.send(.buttonDown(3)), .consume)
        permissions.inputMonitoringAllowed = false

        XCTAssertEqual(backend.send(.disabled(.userInput)), .passThrough)
        XCTAssertEqual(
            controller.status,
            .partiallyRunning(combined, unavailablePermissions: [.inputMonitoring])
        )
        XCTAssertEqual(
            backend.installedConfigurations.last,
            EventTapConfiguration(reverseMouseScroll: false, sideButtonNavigation: true)
        )
        XCTAssertEqual(backend.captureSideButtonsValues.last, true)
        XCTAssertEqual(backend.enableCount, 0)

        let wheel = ScrollObservation(
            timestampNanoseconds: 1,
            isContinuous: false,
            deltas: .init(
                verticalLine: 1,
                verticalPoint: 10,
                verticalFixed: 65_536,
                horizontalLine: 0,
                horizontalPoint: 0,
                horizontalFixed: 0
            ),
            phase: [],
            momentumPhase: []
        )
        XCTAssertEqual(backend.send(.scroll(wheel)), .passThrough)
        XCTAssertEqual(backend.send(.buttonDown(3)), .consume)
        XCTAssertEqual(backend.send(.buttonUp(3)), .consume)
        XCTAssertEqual(backend.send(.buttonDown(4)), .consume)
        XCTAssertEqual(backend.send(.buttonUp(4)), .consume)
        XCTAssertEqual(synthesizer.directions, [.back, .forward])
    }

    func testCombinedStartWithMissingInputMonitoringRunsSideButtonsOnly() {
        let (controller, _, backend, synthesizer) = makeController(
            accessibility: true,
            inputMonitoring: false
        )
        let combined = EventTapConfiguration(
            reverseMouseScroll: true,
            sideButtonNavigation: true
        )

        XCTAssertEqual(
            controller.start(configuration: combined),
            .partiallyRunning(combined, unavailablePermissions: [.inputMonitoring])
        )
        XCTAssertEqual(
            backend.installedConfigurations,
            [EventTapConfiguration(reverseMouseScroll: false, sideButtonNavigation: true)]
        )
        XCTAssertEqual(backend.send(.buttonDown(3)), .consume)
        XCTAssertEqual(backend.send(.buttonUp(3)), .consume)
        XCTAssertEqual(synthesizer.directions, [.back])
    }

    func testRecoveryFailureResetsOwnedPressBeforeLaterSuccessfulStart() {
        let (controller, _, backend, synthesizer) = makeController(
            accessibility: true,
            inputMonitoring: false
        )
        let navigation = EventTapConfiguration(
            reverseMouseScroll: false,
            sideButtonNavigation: true
        )
        _ = controller.start(configuration: navigation)
        XCTAssertEqual(backend.send(.buttonDown(3)), .consume)
        backend.enableError = TestTapError.failure

        XCTAssertEqual(backend.send(.disabled(.timeout)), .passThrough)
        XCTAssertEqual(controller.status, .failed(.eventTapRecoveryFailed))
        XCTAssertEqual(backend.send(.buttonUp(3)), .passThrough)

        backend.enableError = nil
        XCTAssertEqual(controller.start(configuration: navigation), .running(navigation))
        XCTAssertEqual(backend.send(.buttonDown(3)), .consume)
        XCTAssertEqual(backend.send(.buttonUp(3)), .consume)
        XCTAssertEqual(synthesizer.directions, [.back, .back])
    }

    func testStopClearsClaimedButtonOwnership() {
        let (controller, _, backend, synthesizer) = makeController(
            accessibility: true,
            inputMonitoring: false
        )
        let configuration = EventTapConfiguration(
            reverseMouseScroll: false,
            sideButtonNavigation: true
        )
        _ = controller.start(configuration: configuration)
        XCTAssertEqual(backend.send(.buttonDown(3)), .consume)
        controller.stop()
        _ = controller.start(configuration: configuration)

        XCTAssertEqual(backend.send(.buttonUp(3)), .passThrough)
        XCTAssertEqual(synthesizer.directions, [.back])
    }

    func testReconfigurationPreservesHeldPressAndPreventsSecondSynthesis() {
        let (controller, _, backend, synthesizer) = makeController(
            accessibility: true,
            inputMonitoring: true
        )
        let navigation = EventTapConfiguration(
            reverseMouseScroll: false,
            sideButtonNavigation: true
        )
        _ = controller.start(configuration: navigation)
        XCTAssertEqual(backend.send(.buttonDown(3)), .consume)

        let navigationAndScroll = EventTapConfiguration(
            reverseMouseScroll: true,
            sideButtonNavigation: true
        )
        XCTAssertEqual(
            controller.start(configuration: navigationAndScroll),
            .running(navigationAndScroll)
        )
        XCTAssertEqual(backend.send(.buttonDown(3)), .consume)
        XCTAssertEqual(backend.send(.buttonUp(3)), .consume)
        XCTAssertEqual(synthesizer.directions, [.back])
    }

    func testReconfigurationPreservesUnownedPressAcrossFocusChange() {
        let permissions = FakePermissions(accessibility: true, inputMonitoring: false)
        let backend = FakeEventTapBackend()
        let provider = MutableEventTapApplicationProvider(application: .init(
            bundleIdentifier: "com.example.Other",
            processIdentifier: 201,
            isActive: true,
            hasFocusedWindow: true
        ))
        let synthesizer = EventTapTestSynthesizer()
        let controller = EventTapController(
            permissions: permissions,
            backend: backend,
            sideButtons: SideButtonController(
                applicationProvider: provider,
                synthesizer: synthesizer
            )
        )
        let navigation = EventTapConfiguration(
            reverseMouseScroll: false,
            sideButtonNavigation: true
        )
        _ = controller.start(configuration: navigation)
        XCTAssertEqual(backend.send(.buttonDown(3)), .passThrough)

        provider.application = .init(
            bundleIdentifier: "com.apple.Safari",
            processIdentifier: 101,
            isActive: true,
            hasFocusedWindow: true
        )
        _ = controller.start(configuration: navigation)
        XCTAssertEqual(backend.send(.buttonDown(3)), .passThrough)
        XCTAssertEqual(backend.send(.buttonUp(3)), .passThrough)
        XCTAssertTrue(synthesizer.directions.isEmpty)
    }

    func testDisablingFeaturesDrainsHeldOwnedPressBeforeRemovingTap() {
        let (controller, _, backend, synthesizer) = makeController(
            accessibility: true,
            inputMonitoring: false
        )
        let navigation = EventTapConfiguration(
            reverseMouseScroll: false,
            sideButtonNavigation: true
        )
        _ = controller.start(configuration: navigation)
        XCTAssertEqual(backend.send(.buttonDown(4)), .consume)

        let disabled = EventTapConfiguration(
            reverseMouseScroll: false,
            sideButtonNavigation: false
        )
        XCTAssertEqual(controller.start(configuration: disabled), .drainingButtonPresses)
        XCTAssertEqual(backend.captureSideButtonsValues.last, true)
        XCTAssertEqual(backend.send(.buttonDown(4)), .consume)
        XCTAssertEqual(backend.send(.buttonUp(4)), .consume)
        XCTAssertEqual(controller.status, .stopped)
        XCTAssertEqual(synthesizer.directions, [.forward])
    }

    func testCallbackFromReplacedTapGenerationCanOnlyPassThrough() {
        let (controller, _, backend, _) = makeController(
            accessibility: true,
            inputMonitoring: true
        )
        _ = controller.start(configuration: .init(
            reverseMouseScroll: true,
            sideButtonNavigation: false
        ))
        let stale = backend.installedHandlers[0]
        _ = controller.start(configuration: .init(
            reverseMouseScroll: false,
            sideButtonNavigation: true
        ))
        let wheel = ScrollObservation(
            timestampNanoseconds: 1,
            isContinuous: false,
            deltas: .init(
                verticalLine: 1,
                verticalPoint: 10,
                verticalFixed: 65_536,
                horizontalLine: 0,
                horizontalPoint: 0,
                horizontalFixed: 0
            ),
            phase: [],
            momentumPhase: []
        )

        XCTAssertEqual(stale(.scroll(wheel)), .passThrough)
        XCTAssertEqual(
            controller.currentConfiguration,
            .init(reverseMouseScroll: false, sideButtonNavigation: true)
        )
    }

    private func makeController(
        accessibility: Bool,
        inputMonitoring: Bool
    ) -> (
        EventTapController,
        FakePermissions,
        FakeEventTapBackend,
        EventTapTestSynthesizer
    ) {
        let permissions = FakePermissions(
            accessibility: accessibility,
            inputMonitoring: inputMonitoring
        )
        let backend = FakeEventTapBackend()
        let synthesizer = EventTapTestSynthesizer()
        let sideButtons = SideButtonController(
            applicationProvider: EventTapTestApplicationProvider(),
            synthesizer: synthesizer
        )
        return (
            EventTapController(
                permissions: permissions,
                backend: backend,
                sideButtons: sideButtons
            ),
            permissions,
            backend,
            synthesizer
        )
    }
}

private enum TestTapError: Error {
    case failure
}

private struct EventTapTestApplicationProvider: FocusedApplicationProviding {
    func focusedApplication() -> FocusedApplication? {
        FocusedApplication(
            bundleIdentifier: "com.apple.Safari",
            processIdentifier: 101,
            isActive: true,
            hasFocusedWindow: true
        )
    }
}

private final class MutableEventTapApplicationProvider: FocusedApplicationProviding, @unchecked Sendable {
    var application: FocusedApplication?

    init(application: FocusedApplication?) {
        self.application = application
    }

    func focusedApplication() -> FocusedApplication? { application }
}

private final class EventTapTestSynthesizer: NavigationSynthesizing, @unchecked Sendable {
    var directions: [NavigationDirection] = []

    func synthesize(_ direction: NavigationDirection, for target: FocusedApplication) -> Bool {
        directions.append(direction)
        return true
    }
}
