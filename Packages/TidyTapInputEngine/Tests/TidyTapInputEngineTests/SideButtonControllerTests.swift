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

    func synthesize(_ direction: NavigationDirection) -> Bool {
        directions.append(direction)
        return succeeds
    }
}

final class SideButtonControllerTests: XCTestCase {
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

    func testInactiveOrUnfocusedSupportedAppPassesThrough() {
        for application in [
            FocusedApplication(
                bundleIdentifier: "com.apple.Safari",
                isActive: false,
                hasFocusedWindow: true
            ),
            FocusedApplication(
                bundleIdentifier: "com.apple.finder",
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
        isActive: true,
        hasFocusedWindow: true
    )
    private static let finder = FocusedApplication(
        bundleIdentifier: "com.apple.finder",
        isActive: true,
        hasFocusedWindow: true
    )
    private static let otherApp = FocusedApplication(
        bundleIdentifier: "com.example.Other",
        isActive: true,
        hasFocusedWindow: true
    )
}
