import XCTest

@MainActor
final class ClipboardPasteFocusRecoveryTests: XCTestCase {
    @MainActor private final class Fixture {
        typealias Focus = ClipboardPasteFocusRecovery.FocusObservation
        typealias Outcome = ClipboardPasteFocusRecovery.Outcome

        var scheduled: [@MainActor () -> Void] = []
        var scheduledDelays: [TimeInterval] = []
        var observations: [Focus] = []
        var targetAppAlive = true
        var targetFrontmost = true
        var pasteboardWrites = 0
        var pasteKeyPosts = 0
        var outcomes: [Outcome] = []
        lazy var recovery = ClipboardPasteFocusRecovery(schedule: { delay, action in
            self.scheduledDelays.append(delay)
            self.scheduled.append(action)
        })

        func start(id: UUID = UUID(), originalCaptured: Bool = true) {
            recovery.start(
                id: id,
                originalCaptured: originalCaptured,
                targetIsReady: { self.targetAppAlive && self.targetFrontmost },
                inspectFocus: { self.observations.removeFirst() },
                paste: {
                    self.pasteboardWrites += 1
                    self.pasteKeyPosts += 1
                    return nil
                },
                completion: { self.outcomes.append($0) }
            )
        }

        func runNextRetry() {
            scheduled.removeFirst()()
        }
    }

    func testTransientNoValuePastesOnlyAfterOriginalReturns() {
        let fixture = Fixture()
        fixture.observations = [.noValue, .original]
        fixture.start()
        XCTAssertEqual(fixture.pasteboardWrites, 0)
        XCTAssertEqual(fixture.pasteKeyPosts, 0)
        fixture.runNextRetry()
        XCTAssertEqual(fixture.outcomes, [.pasted(error: nil, retries: 1)])
        XCTAssertEqual(fixture.pasteboardWrites, 1)
        XCTAssertEqual(fixture.pasteKeyPosts, 1)
    }

    func testPersistentNoValueStopsAfterFiveAdditionalChecks() {
        let fixture = Fixture()
        fixture.observations = Array(repeating: .noValue, count: 6)
        fixture.start()
        for _ in 0..<5 { fixture.runNextRetry() }
        XCTAssertEqual(fixture.outcomes, [
            .failed(reason: "focusChanged", retries: 5, axError: -25212, originalMatched: false)
        ])
        XCTAssertEqual(fixture.scheduledDelays, Array(repeating: 0.03, count: 5))
        XCTAssertTrue(fixture.scheduled.isEmpty)
        XCTAssertEqual(fixture.pasteboardWrites, 0)
        XCTAssertEqual(fixture.pasteKeyPosts, 0)
    }

    func testDifferentElementAfterNoValueStopsWithoutPaste() {
        let fixture = Fixture()
        fixture.observations = [.noValue, .different]
        fixture.start()
        fixture.runNextRetry()
        XCTAssertEqual(fixture.outcomes, [
            .failed(reason: "focusChanged", retries: 1, axError: nil, originalMatched: false)
        ])
        XCTAssertEqual(fixture.pasteboardWrites, 0)
        XCTAssertEqual(fixture.pasteKeyPosts, 0)
    }

    func testMissingOriginalElementNeverInspectsOrPastes() {
        let fixture = Fixture()
        fixture.start(originalCaptured: false)
        XCTAssertEqual(fixture.outcomes, [
            .failed(reason: "focusChanged", retries: 0, axError: nil, originalMatched: false)
        ])
        XCTAssertEqual(fixture.pasteboardWrites, 0)
        XCTAssertEqual(fixture.pasteKeyPosts, 0)
    }

    func testTargetExitOrAppSwitchDuringRetryStopsWithoutPaste() {
        for appExited in [true, false] {
            let fixture = Fixture()
            fixture.observations = [.noValue, .original]
            fixture.start()
            if appExited { fixture.targetAppAlive = false }
            else { fixture.targetFrontmost = false }
            fixture.runNextRetry()
            XCTAssertEqual(fixture.outcomes, [
                .failed(reason: "targetUnavailable", retries: 1, axError: nil, originalMatched: false)
            ])
            XCTAssertEqual(fixture.observations, [.original])
            XCTAssertEqual(fixture.pasteboardWrites, 0)
            XCTAssertEqual(fixture.pasteKeyPosts, 0)
        }
    }

    func testNewRequestSupersedesOldRetryWithoutLatePasteOrResult() {
        let fixture = Fixture()
        fixture.observations = [.noValue]
        fixture.start()
        fixture.observations = [.original]
        fixture.start()
        XCTAssertEqual(fixture.outcomes, [.superseded, .pasted(error: nil, retries: 0)])
        fixture.runNextRetry()
        XCTAssertEqual(fixture.outcomes, [.superseded, .pasted(error: nil, retries: 0)])
        XCTAssertEqual(fixture.pasteboardWrites, 1)
        XCTAssertEqual(fixture.pasteKeyPosts, 1)
    }

    func testTargetLeavesForegroundDuringFocusQueryBeforePaste() {
        var targetFrontmost = true
        var pasteboardWrites = 0
        var pasteKeyPosts = 0
        var outcomes: [ClipboardPasteFocusRecovery.Outcome] = []
        let recovery = ClipboardPasteFocusRecovery(schedule: { _, _ in
            XCTFail("A matching focus must not schedule a retry")
        })
        recovery.start(
            id: UUID(), originalCaptured: true,
            targetIsReady: { targetFrontmost },
            inspectFocus: {
                targetFrontmost = false
                return .original
            },
            paste: {
                pasteboardWrites += 1
                pasteKeyPosts += 1
                return nil
            },
            completion: { outcomes.append($0) }
        )
        XCTAssertEqual(outcomes, [
            .failed(reason: "targetUnavailable", retries: 0, axError: nil, originalMatched: true)
        ])
        XCTAssertEqual(pasteboardWrites, 0)
        XCTAssertEqual(pasteKeyPosts, 0)
    }

    func testOtherAXErrorFailsImmediately() {
        let fixture = Fixture()
        fixture.observations = [.otherError(-25211)]
        fixture.start()
        XCTAssertEqual(fixture.outcomes, [
            .failed(reason: "focusChanged", retries: 0, axError: -25211, originalMatched: false)
        ])
        XCTAssertTrue(fixture.scheduled.isEmpty)
        XCTAssertEqual(fixture.pasteboardWrites, 0)
        XCTAssertEqual(fixture.pasteKeyPosts, 0)
    }
}
