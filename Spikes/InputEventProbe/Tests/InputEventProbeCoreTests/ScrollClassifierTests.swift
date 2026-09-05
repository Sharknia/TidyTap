import XCTest
@testable import InputEventProbeCore

final class ScrollClassifierTests: XCTestCase {
    func testDiscreteLineScrollIsMouse() {
        var classifier = ScrollClassifier()

        XCTAssertEqual(
            classifier.classify(observation(continuous: false, vertical: 1)),
            .discreteMouse
        )
    }

    func testDiscreteEventWithoutLineDeltaIsUnknown() {
        var classifier = ScrollClassifier()

        XCTAssertEqual(classifier.classify(observation(continuous: false)), .unknown)
    }

    func testContinuousDirectGestureIsTrackpad() {
        var classifier = ScrollClassifier()

        XCTAssertEqual(
            classifier.classify(observation(continuous: true, phase: .began)),
            .trackpad
        )
        XCTAssertEqual(
            classifier.classify(observation(time: 10, continuous: true, phase: .changed)),
            .trackpad
        )
    }

    func testMomentumLinksToRecentGestureAndRemainsLinkedPastWindow() {
        var classifier = ScrollClassifier(linkWindowNanoseconds: 100)
        _ = classifier.classify(observation(time: 10, continuous: true, phase: .ended))

        XCTAssertEqual(
            classifier.classify(observation(time: 50, continuous: true, momentum: .began)),
            .trackpad
        )
        XCTAssertEqual(
            classifier.classify(observation(time: 1_000, continuous: true, momentum: .changed)),
            .trackpad
        )
        XCTAssertEqual(
            classifier.classify(observation(time: 2_000, continuous: true, momentum: .ended)),
            .trackpad
        )
        XCTAssertEqual(
            classifier.classify(observation(time: 2_001, continuous: true, momentum: .changed)),
            .unknown
        )
    }

    func testUnlinkedContinuousAndMomentumAreUnknown() {
        var classifier = ScrollClassifier(linkWindowNanoseconds: 100)

        XCTAssertEqual(classifier.classify(observation(time: 500, continuous: true)), .unknown)
        XCTAssertEqual(
            classifier.classify(observation(time: 500, continuous: true, momentum: .began)),
            .unknown
        )
    }

    func testPublicGestureSignalLinksNearbyContinuousScroll() {
        var classifier = ScrollClassifier(linkWindowNanoseconds: 100)
        classifier.observeGesture(at: 1_000)

        XCTAssertEqual(classifier.classify(observation(time: 1_050, continuous: true)), .trackpad)
        XCTAssertEqual(classifier.classify(observation(time: 1_101, continuous: true)), .unknown)
    }

    func testOldGestureDoesNotLinkMomentum() {
        var classifier = ScrollClassifier(linkWindowNanoseconds: 100)
        classifier.observeGesture(at: 1_000)

        XCTAssertEqual(
            classifier.classify(observation(time: 1_101, continuous: true, momentum: .began)),
            .unknown
        )
    }

    private func observation(
        time: UInt64 = 0,
        continuous: Bool,
        vertical: Int64 = 0,
        horizontal: Int64 = 0,
        phase: ScrollPhaseBits = [],
        momentum: ScrollPhaseBits = []
    ) -> ScrollObservation {
        ScrollObservation(
            timestampNanoseconds: time,
            isContinuous: continuous,
            verticalLineDelta: vertical,
            horizontalLineDelta: horizontal,
            phase: phase,
            momentumPhase: momentum
        )
    }
}

final class ButtonPressOwnershipTests: XCTestCase {
    func testOwnedCallbackConsumesFirstDownRepeatsAndMatchingUp() {
        var ownership = ButtonPressOwnership()

        XCTAssertEqual(ownership.registerDown(button: 3), .firstDown)
        XCTAssertTrue(ownership.claimPress(button: 3))
        XCTAssertEqual(ownership.registerDown(button: 3), .repeatedOwned)
        XCTAssertEqual(ownership.registerDown(button: 3), .repeatedOwned)
        XCTAssertTrue(ownership.registerUp(button: 3))
        XCTAssertEqual(ownership.registerDown(button: 3), .firstDown)
    }

    func testUnownedCallbackPassesEveryEventThrough() {
        var ownership = ButtonPressOwnership()

        XCTAssertEqual(ownership.registerDown(button: 3), .firstDown)
        XCTAssertEqual(ownership.registerDown(button: 3), .repeatedUnowned)
        XCTAssertEqual(ownership.registerDown(button: 3), .repeatedUnowned)
        XCTAssertFalse(ownership.registerUp(button: 3))
    }

    func testCannotClaimWithoutFirstDown() {
        var ownership = ButtonPressOwnership()

        XCTAssertFalse(ownership.claimPress(button: 3))
        XCTAssertFalse(ownership.registerUp(button: 3))
    }

    func testButtonsHaveIndependentOwnership() {
        var ownership = ButtonPressOwnership()

        XCTAssertEqual(ownership.registerDown(button: 3), .firstDown)
        XCTAssertTrue(ownership.claimPress(button: 3))
        XCTAssertEqual(ownership.registerDown(button: 4), .firstDown)
        XCTAssertEqual(ownership.registerDown(button: 3), .repeatedOwned)
        XCTAssertEqual(ownership.registerDown(button: 4), .repeatedUnowned)
        XCTAssertFalse(ownership.registerUp(button: 4))
        XCTAssertTrue(ownership.registerUp(button: 3))
    }
}

final class ButtonCallbackStateTests: XCTestCase {
    func testClaimedSafariOrFinderPressSynthesizesOnceAndConsumesWholePair() {
        var callbacks = ButtonCallbackState()
        var synthesisAttempts = 0

        XCTAssertEqual(
            callbacks.buttonDown(button: 3, isEligibleNavigationTarget: true),
            .attemptNavigation
        )
        synthesisAttempts += 1
        XCTAssertTrue(callbacks.navigationDidSucceed(button: 3))

        XCTAssertEqual(
            callbacks.buttonDown(button: 3, isEligibleNavigationTarget: true),
            .consume
        )
        XCTAssertEqual(
            callbacks.buttonDown(button: 3, isEligibleNavigationTarget: false),
            .consume,
            "a claimed press remains owned even if focus changes before release"
        )
        XCTAssertEqual(callbacks.buttonUp(button: 3), .consume)
        XCTAssertEqual(synthesisAttempts, 1)
    }

    func testOtherAppPressPassesEveryCallbackThroughEvenIfFocusChangesMidPress() {
        var callbacks = ButtonCallbackState()

        XCTAssertEqual(
            callbacks.buttonDown(button: 4, isEligibleNavigationTarget: false),
            .passThrough
        )
        XCTAssertEqual(
            callbacks.buttonDown(button: 4, isEligibleNavigationTarget: true),
            .passThrough,
            "a repeat may not claim a press that began in another app"
        )
        XCTAssertEqual(callbacks.buttonUp(button: 4), .passThrough)
    }

    func testFailedSynthesisDoesNotClaimRepeatsOrUp() {
        var callbacks = ButtonCallbackState()

        XCTAssertEqual(
            callbacks.buttonDown(button: 3, isEligibleNavigationTarget: true),
            .attemptNavigation
        )
        // The callback intentionally does not call navigationDidSucceed.
        XCTAssertEqual(
            callbacks.buttonDown(button: 3, isEligibleNavigationTarget: true),
            .passThrough
        )
        XCTAssertEqual(callbacks.buttonUp(button: 3), .passThrough)
    }
}
