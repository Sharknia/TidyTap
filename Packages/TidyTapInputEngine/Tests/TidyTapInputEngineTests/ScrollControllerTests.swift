import XCTest
@testable import TidyTapInputEngine

final class ScrollControllerTests: XCTestCase {
    func testDiscreteMouseInvertsEveryVerticalRepresentationOnly() {
        var controller = ScrollController()
        let input = observation(
            continuous: false,
            deltas: deltas(
                verticalLine: 3,
                verticalPoint: 17,
                verticalFixed: 196_608,
                horizontalLine: -2,
                horizontalPoint: -11,
                horizontalFixed: -131_072
            )
        )

        let result = controller.process(input)

        XCTAssertEqual(result.classification, .discreteMouse)
        XCTAssertTrue(result.didInvert)
        XCTAssertEqual(
            result.outputDeltas,
            deltas(
                verticalLine: -3,
                verticalPoint: -17,
                verticalFixed: -196_608,
                horizontalLine: -2,
                horizontalPoint: -11,
                horizontalFixed: -131_072
            )
        )
    }

    func testHorizontalOnlyDiscreteScrollIsNeverChanged() {
        var controller = ScrollController()
        let original = deltas(horizontalLine: 2, horizontalPoint: 10, horizontalFixed: 20)

        let result = controller.process(observation(continuous: false, deltas: original))

        XCTAssertEqual(result.classification, .discreteMouse)
        XCTAssertFalse(result.didInvert)
        XCTAssertEqual(result.outputDeltas, original)
    }

    func testUnknownContinuousScrollIsUnchanged() {
        var controller = ScrollController()
        let original = deltas(verticalLine: 2, verticalPoint: 9, verticalFixed: 10)

        let result = controller.process(observation(continuous: true, deltas: original))

        XCTAssertEqual(result.classification, .unknown)
        XCTAssertFalse(result.didInvert)
        XCTAssertEqual(result.outputDeltas, original)
    }

    func testDirectTrackpadAndLinkedMomentumRemainUnchanged() {
        var controller = ScrollController(
            classifier: ScrollClassifier(linkWindowNanoseconds: 100)
        )
        let original = deltas(verticalLine: 1, verticalPoint: 2, verticalFixed: 3)

        let direct = controller.process(
            observation(time: 10, continuous: true, deltas: original, phase: .ended)
        )
        let momentumBegin = controller.process(
            observation(time: 50, continuous: true, deltas: original, momentum: .began)
        )
        let momentumLate = controller.process(
            observation(time: 1_000, continuous: true, deltas: original, momentum: .changed)
        )

        XCTAssertEqual(direct.classification, .trackpad)
        XCTAssertEqual(momentumBegin.classification, .trackpad)
        XCTAssertEqual(momentumLate.classification, .trackpad)
        XCTAssertFalse(direct.didInvert)
        XCTAssertFalse(momentumBegin.didInvert)
        XCTAssertFalse(momentumLate.didInvert)
    }

    func testPublicGestureLinksOnlyNearbyContinuousScroll() {
        var controller = ScrollController(
            classifier: ScrollClassifier(linkWindowNanoseconds: 100)
        )
        controller.observeGesture(at: 1_000)

        XCTAssertEqual(
            controller.process(observation(time: 1_100, continuous: true)).classification,
            .trackpad
        )
        XCTAssertEqual(
            controller.process(observation(time: 1_101, continuous: true)).classification,
            .unknown
        )
    }

    func testZeroDeltaDiscreteEventIsUnknown() {
        var controller = ScrollController()
        XCTAssertEqual(
            controller.process(observation(continuous: false)).classification,
            .unknown
        )
    }

    func testOverflowingDeltaPassesThroughInsteadOfTrapping() {
        var controller = ScrollController()
        let original = deltas(verticalLine: 1, verticalPoint: Int64.min, verticalFixed: 2)

        let result = controller.process(observation(continuous: false, deltas: original))

        XCTAssertEqual(result.classification, .discreteMouse)
        XCTAssertFalse(result.didInvert)
        XCTAssertEqual(result.outputDeltas, original)
    }

    private func observation(
        time: UInt64 = 0,
        continuous: Bool,
        deltas: ScrollDeltaFields = ScrollControllerTests.deltas(),
        phase: ScrollPhaseBits = [],
        momentum: ScrollPhaseBits = []
    ) -> ScrollObservation {
        ScrollObservation(
            timestampNanoseconds: time,
            isContinuous: continuous,
            deltas: deltas,
            phase: phase,
            momentumPhase: momentum
        )
    }

    private static func deltas(
        verticalLine: Int64 = 0,
        verticalPoint: Int64 = 0,
        verticalFixed: Int64 = 0,
        horizontalLine: Int64 = 0,
        horizontalPoint: Int64 = 0,
        horizontalFixed: Int64 = 0
    ) -> ScrollDeltaFields {
        ScrollDeltaFields(
            verticalLine: verticalLine,
            verticalPoint: verticalPoint,
            verticalFixed: verticalFixed,
            horizontalLine: horizontalLine,
            horizontalPoint: horizontalPoint,
            horizontalFixed: horizontalFixed
        )
    }

    private func deltas(
        verticalLine: Int64 = 0,
        verticalPoint: Int64 = 0,
        verticalFixed: Int64 = 0,
        horizontalLine: Int64 = 0,
        horizontalPoint: Int64 = 0,
        horizontalFixed: Int64 = 0
    ) -> ScrollDeltaFields {
        Self.deltas(
            verticalLine: verticalLine,
            verticalPoint: verticalPoint,
            verticalFixed: verticalFixed,
            horizontalLine: horizontalLine,
            horizontalPoint: horizontalPoint,
            horizontalFixed: horizontalFixed
        )
    }
}
