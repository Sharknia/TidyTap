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

final class ButtonPressGateTests: XCTestCase {
    func testOneDownPerPressAndMatchingUp() {
        var gate = ButtonPressGate()

        XCTAssertTrue(gate.registerDown(button: 3))
        XCTAssertFalse(gate.registerDown(button: 3))
        XCTAssertTrue(gate.registerUp(button: 3))
        XCTAssertFalse(gate.registerUp(button: 3))
        XCTAssertTrue(gate.registerDown(button: 3))
    }

    func testButtonsHaveIndependentState() {
        var gate = ButtonPressGate()

        XCTAssertTrue(gate.registerDown(button: 3))
        XCTAssertTrue(gate.registerDown(button: 4))
        XCTAssertTrue(gate.registerUp(button: 4))
        XCTAssertTrue(gate.registerUp(button: 3))
    }
}
