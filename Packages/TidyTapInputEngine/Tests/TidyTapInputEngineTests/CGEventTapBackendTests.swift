import ApplicationServices
import XCTest
@testable import TidyTapInputEngine

final class CGEventTapBackendTests: XCTestCase {
    func testClipboardShortcutConsumesOnePressAndItsKeyUpWithoutLeakingOtherKeys() throws {
        let calls = ShortcutCallCount()
        let backend = CGEventTapBackend(clipboardShortcutHandler: { calls.record() })
        backend.setClipboardShortcut(.init(keyCode: 8, modifiers: CGEventFlags.maskAlternate.rawValue))

        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true))
        down.flags = .maskAlternate
        XCTAssertTrue(backend.handleClipboardShortcut(type: .keyDown, event: down))
        down.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
        XCTAssertTrue(backend.handleClipboardShortcut(type: .keyDown, event: down))

        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false))
        XCTAssertTrue(backend.handleClipboardShortcut(type: .keyUp, event: up))
        XCTAssertFalse(backend.handleClipboardShortcut(type: .keyUp, event: up))
        let other = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: true))
        other.flags = .maskAlternate
        XCTAssertFalse(backend.handleClipboardShortcut(type: .keyDown, event: other))
        XCTAssertEqual(calls.value, 1)

        backend.setClipboardShortcut(.init(keyCode: 8, modifiers: CGEventFlags.maskAlternate.rawValue))
        XCTAssertTrue(backend.handleClipboardShortcut(type: .keyDown, event: down))
        XCTAssertTrue(backend.handleClipboardShortcut(type: .keyUp, event: up))
        XCTAssertEqual(calls.value, 1, "joining a held key repeat must not open the window")
    }

    func testFixedStepUsesActualLineSetterWithoutReinjectingPointOrFixedDeltas() throws {
        let actual = try makeScrollEvent()
        let nativeReference = try makeScrollEvent()
        let originalPoint = actual.getIntegerValueField(.scrollWheelEventPointDeltaAxis1)
        let originalFixed = actual.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1)

        nativeReference.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 6)
        _ = CGEventTapBackend.apply(.setVerticalScrollStep(lines: 6), to: actual)

        let fields: [CGEventField] = [
            .scrollWheelEventDeltaAxis1,
            .scrollWheelEventPointDeltaAxis1,
            .scrollWheelEventFixedPtDeltaAxis1,
            .scrollWheelEventDeltaAxis2,
            .scrollWheelEventPointDeltaAxis2,
            .scrollWheelEventFixedPtDeltaAxis2
        ]
        for field in fields {
            XCTAssertEqual(
                actual.getIntegerValueField(field),
                nativeReference.getIntegerValueField(field),
                "backend output must exactly match applying only the native axis-1 line setter"
            )
        }
        XCTAssertNotEqual(
            actual.getIntegerValueField(.scrollWheelEventPointDeltaAxis1),
            originalPoint,
            "the test must observe the native line setter updating point delta"
        )
        XCTAssertNotEqual(
            actual.getIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1),
            originalFixed,
            "the test must observe the native line setter updating fixed-point delta"
        )
    }

    private func makeScrollEvent() throws -> CGEvent {
        guard let event = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .line,
            wheelCount: 2,
            wheel1: 1,
            wheel2: -2,
            wheel3: 0
        ) else {
            throw CGEventTestError.creationFailed
        }
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis1, value: 37)
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 222_222)
        event.setIntegerValueField(.scrollWheelEventPointDeltaAxis2, value: -13)
        event.setIntegerValueField(.scrollWheelEventFixedPtDeltaAxis2, value: -333_333)
        return event
    }
}

private final class ShortcutCallCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }

    func record() {
        lock.lock()
        count += 1
        lock.unlock()
    }
}

private enum CGEventTestError: Error {
    case creationFailed
}
