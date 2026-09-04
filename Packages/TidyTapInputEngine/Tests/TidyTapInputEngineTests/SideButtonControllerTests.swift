import XCTest
@testable import TidyTapInputEngine

private final class FakeFocusedApplicationProvider: FocusedApplicationProviding, @unchecked Sendable {
    var application: FocusedApplication?
    var callCount = 0

    init(_ application: FocusedApplication?) {
        self.application = application
    }

    func focusedApplication() -> FocusedApplication? {
        callCount += 1
        return application
    }
}

private final class FakeNavigationSynthesizer: NavigationSynthesizing, @unchecked Sendable {
    var succeeds = true
    var directions: [NavigationDirection] = []
    var targets: [FocusedApplication] = []

    func synthesize(_ direction: NavigationDirection, for target: FocusedApplication) -> Bool {
        directions.append(direction)
        targets.append(target)
        return succeeds
    }
}

private final class FakeTargetedPoster: ProcessTargetedNavigationPosting, @unchecked Sendable {
    var posts: [(NavigationDirection, pid_t)] = []

    func post(_ direction: NavigationDirection, to processIdentifier: pid_t) -> Bool {
        posts.append((direction, processIdentifier))
        return true
    }
}

final class SideButtonControllerTests: XCTestCase {
    func testProductionSynthesizerRevalidatesFocusAndTargetsValidatedPID() {
        let provider = FakeFocusedApplicationProvider(Self.otherApp)
        let poster = FakeTargetedPoster()
        let synthesizer = CGNavigationSynthesizer(
            applicationProvider: provider,
            eventPoster: poster
        )

        XCTAssertFalse(synthesizer.synthesize(.back, for: Self.safari))
        XCTAssertTrue(poster.posts.isEmpty, "focus changed before synthesis")

        provider.application = Self.safari
        XCTAssertTrue(synthesizer.synthesize(.back, for: Self.safari))
        XCTAssertEqual(poster.posts.count, 1)
        XCTAssertEqual(poster.posts[0].0, .back)
        XCTAssertEqual(poster.posts[0].1, Self.safari.processIdentifier)
    }

    func testSafariPressSynthesizesOnceAndOwnsRepeatsAndUpAcrossFocusChange() {
        let provider = FakeFocusedApplicationProvider(Self.safari)
        let synthesizer = FakeNavigationSynthesizer()
        let controller = SideButtonController(
            applicationProvider: provider,
            synthesizer: synthesizer
        )

        XCTAssertEqual(controller.handleButtonDown(3), .consume)
        provider.application = Self.otherApp
        XCTAssertEqual(controller.handleButtonDown(3), .consume)
        XCTAssertEqual(controller.handleButtonDown(3), .consume)
        XCTAssertEqual(controller.handleButtonUp(3), .consume)
        XCTAssertEqual(synthesizer.directions, [.back])
        XCTAssertEqual(provider.callCount, 1)
    }

    func testPressStartedInOtherAppNeverBecomesOwnedAfterFocusChange() {
        let provider = FakeFocusedApplicationProvider(Self.otherApp)
        let synthesizer = FakeNavigationSynthesizer()
        let controller = SideButtonController(
            applicationProvider: provider,
            synthesizer: synthesizer
        )

        XCTAssertEqual(controller.handleButtonDown(4), .passThrough)
        provider.application = Self.finder
        XCTAssertEqual(controller.handleButtonDown(4), .passThrough)
        XCTAssertEqual(controller.handleButtonUp(4), .passThrough)
        XCTAssertEqual(synthesizer.directions, [])
        XCTAssertEqual(provider.callCount, 1)
    }

    func testFailedSynthesisDoesNotClaimPress() {
        let provider = FakeFocusedApplicationProvider(Self.safari)
        let synthesizer = FakeNavigationSynthesizer()
        synthesizer.succeeds = false
        let controller = SideButtonController(
            applicationProvider: provider,
            synthesizer: synthesizer
        )

        XCTAssertEqual(controller.handleButtonDown(3), .passThrough)
        XCTAssertEqual(controller.handleButtonDown(3), .passThrough)
        XCTAssertEqual(controller.handleButtonUp(3), .passThrough)
        XCTAssertEqual(synthesizer.directions, [.back])
    }

    func testFocusRaceRejectedBySynthesizerNeverClaimsOrConsumesPress() {
        let provider = FakeFocusedApplicationProvider(Self.safari)
        let synthesizer = FakeNavigationSynthesizer()
        synthesizer.succeeds = false // Production returns false when its immediate PID recheck differs.
        let controller = SideButtonController(
            applicationProvider: provider,
            synthesizer: synthesizer
        )

        XCTAssertEqual(controller.handleButtonDown(4), .passThrough)
        provider.application = Self.otherApp
        XCTAssertEqual(controller.handleButtonDown(4), .passThrough)
        XCTAssertEqual(controller.handleButtonUp(4), .passThrough)
        XCTAssertEqual(synthesizer.directions, [.forward])
        XCTAssertEqual(synthesizer.targets.map(\.processIdentifier), [101])
    }

    func testInactiveOrUnfocusedSupportedAppPassesThrough() {
        for application in [
            FocusedApplication(
                bundleIdentifier: "com.apple.Safari",
                processIdentifier: 101,
                isActive: false,
                hasFocusedWindow: true
            ),
            FocusedApplication(
                bundleIdentifier: "com.apple.finder",
                processIdentifier: 102,
                isActive: true,
                hasFocusedWindow: false
            )
        ] {
            let synthesizer = FakeNavigationSynthesizer()
            let controller = SideButtonController(
                applicationProvider: FakeFocusedApplicationProvider(application),
                synthesizer: synthesizer
            )
            XCTAssertEqual(controller.handleButtonDown(3), .passThrough)
            XCTAssertEqual(controller.handleButtonUp(3), .passThrough)
            XCTAssertTrue(synthesizer.directions.isEmpty)
        }
    }

    func testOnlyButtonsThreeAndFourAreHandled() {
        let provider = FakeFocusedApplicationProvider(Self.safari)
        let synthesizer = FakeNavigationSynthesizer()
        let controller = SideButtonController(
            applicationProvider: provider,
            synthesizer: synthesizer
        )

        XCTAssertEqual(controller.handleButtonDown(2), .passThrough)
        XCTAssertEqual(controller.handleButtonUp(2), .passThrough)
        XCTAssertEqual(provider.callCount, 0)
        XCTAssertEqual(SideButtonController.direction(for: 3), .back)
        XCTAssertEqual(SideButtonController.direction(for: 4), .forward)
    }

    func testResetReleasesAllOwnershipWithoutSynthesizingAnything() {
        let provider = FakeFocusedApplicationProvider(Self.finder)
        let synthesizer = FakeNavigationSynthesizer()
        let controller = SideButtonController(
            applicationProvider: provider,
            synthesizer: synthesizer
        )
        XCTAssertEqual(controller.handleButtonDown(4), .consume)

        controller.reset()

        XCTAssertEqual(controller.handleButtonUp(4), .passThrough)
        XCTAssertEqual(synthesizer.directions, [.forward])
    }

    private static let safari = FocusedApplication(
        bundleIdentifier: "com.apple.Safari",
        processIdentifier: 101,
        isActive: true,
        hasFocusedWindow: true
    )
    private static let finder = FocusedApplication(
        bundleIdentifier: "com.apple.finder",
        processIdentifier: 102,
        isActive: true,
        hasFocusedWindow: true
    )
    private static let otherApp = FocusedApplication(
        bundleIdentifier: "com.example.Other",
        processIdentifier: 103,
        isActive: true,
        hasFocusedWindow: true
    )
}
