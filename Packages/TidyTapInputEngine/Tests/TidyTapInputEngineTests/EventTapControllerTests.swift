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
    var installCount = 0
    var enableCount = 0
    var uninstallCount = 0
    var installError: Error?
    var enableError: Error?

    func install(
        configuration: EventTapConfiguration,
        handler: @escaping EventTapHandler
    ) throws {
        installCount += 1
        if let installError { throw installError }
        self.handler = handler
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
            isActive: true,
            hasFocusedWindow: true
        )
    }
}

private final class EventTapTestSynthesizer: NavigationSynthesizing, @unchecked Sendable {
    var directions: [NavigationDirection] = []

    func synthesize(_ direction: NavigationDirection) -> Bool {
        directions.append(direction)
        return true
    }
}
