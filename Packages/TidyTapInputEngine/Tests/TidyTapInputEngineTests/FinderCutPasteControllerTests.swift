import Foundation
import XCTest
@testable import TidyTapInputEngine

private final class FakeFinderEnvironment: FinderCutPasteEnvironment, @unchecked Sendable {
    private let lock = NSLock()
    private var storedContext: FinderContext? = .init(processIdentifier: 42, windowIdentifier: 7)
    private var storedSnapshot = FinderPasteboardSnapshot(changeCount: 1, containsFiles: true)
    private var storedSelectionIdentifier: UInt = 1
    private var storedAnchorRect: CGRect? = .init(x: 100, y: 200, width: 40, height: 18)
    var onDeferredMove: (() -> Void)?
    var onSelectionSnapshot: (() -> Void)?
    var deferredMoveSucceeds = true

    var context: FinderContext? {
        get { withLock { storedContext } }
        set { withLock { storedContext = newValue } }
    }

    var snapshot: FinderPasteboardSnapshot {
        get { withLock { storedSnapshot } }
        set { withLock { storedSnapshot = newValue } }
    }

    var selectionIdentifier: UInt {
        get { withLock { storedSelectionIdentifier } }
        set { withLock { storedSelectionIdentifier = newValue } }
    }

    var anchorRect: CGRect? {
        get { withLock { storedAnchorRect } }
        set { withLock { storedAnchorRect = newValue } }
    }

    func focusedFileListContext() -> FinderContext? { context }
    func pasteboardSnapshot() -> FinderPasteboardSnapshot { snapshot }
    func selectionSnapshot() -> FinderSelectionSnapshot? {
        onSelectionSnapshot?()
        guard let context else { return nil }
        let target = anchorRect.map {
            FinderFeedbackTarget(
                context: context,
                selectionIdentifier: selectionIdentifier,
                anchorRect: $0
            )
        }
        return .init(context: context, feedbackTarget: target)
    }
    func prepareDeferredMove() -> (@Sendable () -> Void)? {
        guard deferredMoveSucceeds else { return nil }
        return { [weak self] in self?.onDeferredMove?() }
    }

    @discardableResult
    private func withLock<T>(_ operation: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return operation()
    }
}

final class FinderCutPasteControllerTests: XCTestCase {
    func testCutArmsOnlyAfterNewFilePasteboardAndMovesOnce() {
        let environment = FakeFinderEnvironment()
        let controller = makeController(environment)

        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: true), .consume)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: false, isRepeat: false), .replaceWithCopy)
        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .consume)

        let moveSent = expectation(description: "deferred move")
        environment.onDeferredMove = { moveSent.fulfill() }
        environment.snapshot = .init(changeCount: 2, containsFiles: true)
        wait(for: [moveSent], timeout: 0.3)

        XCTAssertEqual(controller.handle(keyCode: 9, isDown: false, isRepeat: false), .consume)
        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .passThrough)
    }

    func testGeneralCopyInvalidatesPendingBeforePasteboardChanges() {
        let environment = FakeFinderEnvironment()
        let controller = makeController(environment)

        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        XCTAssertEqual(controller.handle(keyCode: 8, isDown: true, isRepeat: false), .passThrough)
        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .passThrough)
        environment.snapshot = .init(changeCount: 2, containsFiles: true)
        Thread.sleep(forTimeInterval: 0.03)
        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .passThrough)
    }

    func testGeneralCopyReportsOnlyAfterFileClipboardAndStableSelection() {
        let environment = FakeFinderEnvironment()
        let received = expectation(description: "copy feedback")
        let controller = makeController(environment) { feedback in
            XCTAssertEqual(feedback.kind, .copyReady)
            XCTAssertEqual(feedback.anchorRect, .init(x: 100, y: 200, width: 40, height: 18))
            XCTAssertEqual(feedback.clipboardChangeCount, 2)
            received.fulfill()
        }

        XCTAssertEqual(controller.handle(keyCode: 8, isDown: true, isRepeat: false), .passThrough)
        environment.snapshot = .init(changeCount: 2, containsFiles: true)
        wait(for: [received], timeout: 0.3)
    }

    func testCutReportsMoveReadyOnlyAfterFileClipboardConfirmation() {
        let environment = FakeFinderEnvironment()
        let received = expectation(description: "move feedback")
        let controller = makeController(environment) { feedback in
            XCTAssertEqual(feedback.kind, .moveReady)
            XCTAssertEqual(feedback.clipboardChangeCount, 2)
            received.fulfill()
        }

        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        environment.snapshot = .init(changeCount: 2, containsFiles: true)
        wait(for: [received], timeout: 0.3)
    }

    func testFeedbackDeliveryIsSerializedBeforeTapInvalidationReturns() {
        let environment = FakeFinderEnvironment()
        let deliveryStarted = expectation(description: "feedback delivery started")
        let releaseDelivery = DispatchSemaphore(value: 0)
        let invalidationReturned = DispatchSemaphore(value: 0)
        let controller = makeController(environment) { _ in
            deliveryStarted.fulfill()
            releaseDelivery.wait()
        }

        XCTAssertEqual(controller.handle(keyCode: 8, isDown: true, isRepeat: false), .passThrough)
        environment.snapshot = .init(changeCount: 2, containsFiles: true)
        wait(for: [deliveryStarted], timeout: 0.3)

        DispatchQueue.global().async {
            controller.resetAfterTapDisable()
            invalidationReturned.signal()
        }
        XCTAssertEqual(invalidationReturned.wait(timeout: .now() + 0.02), .timedOut)
        releaseDelivery.signal()
        XCTAssertEqual(invalidationReturned.wait(timeout: .now() + 0.3), .success)
    }

    func testDeferredMovePostIsSerializedBeforeTapInvalidationReturns() {
        let environment = FakeFinderEnvironment()
        let postStarted = expectation(description: "deferred move post started")
        let releasePost = DispatchSemaphore(value: 0)
        let invalidationReturned = DispatchSemaphore(value: 0)
        environment.onDeferredMove = {
            postStarted.fulfill()
            releasePost.wait()
        }
        let controller = makeController(environment)

        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .consume)
        environment.snapshot = .init(changeCount: 2, containsFiles: true)
        wait(for: [postStarted], timeout: 0.3)

        DispatchQueue.global().async {
            controller.resetAfterTapDisable()
            invalidationReturned.signal()
        }
        XCTAssertEqual(invalidationReturned.wait(timeout: .now() + 0.02), .timedOut)
        releasePost.signal()
        XCTAssertEqual(invalidationReturned.wait(timeout: .now() + 0.3), .success)
    }

    func testGeneralCopyDoesNotReportWhenSelectionChangesBeforeClipboardConfirmation() {
        let environment = FakeFinderEnvironment()
        let notReceived = expectation(description: "no copy feedback")
        notReceived.isInverted = true
        let controller = makeController(environment) { _ in notReceived.fulfill() }

        XCTAssertEqual(controller.handle(keyCode: 8, isDown: true, isRepeat: false), .passThrough)
        environment.selectionIdentifier = 2
        environment.snapshot = .init(changeCount: 2, containsFiles: true)
        wait(for: [notReceived], timeout: 0.08)
    }

    func testCutDoesNotReportWhenSelectionChangesBeforeClipboardConfirmation() {
        let environment = FakeFinderEnvironment()
        let notReceived = expectation(description: "no move feedback")
        notReceived.isInverted = true
        let controller = makeController(environment) { _ in notReceived.fulfill() }

        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        environment.selectionIdentifier = 2
        environment.snapshot = .init(changeCount: 2, containsFiles: true)
        wait(for: [notReceived], timeout: 0.08)
    }

    func testFeedbackIsSkippedWhenAnchorCaptureFailsWithoutBreakingCut() {
        let environment = FakeFinderEnvironment()
        environment.anchorRect = nil
        let notReceived = expectation(description: "no feedback")
        notReceived.isInverted = true
        let controller = makeController(environment) { _ in notReceived.fulfill() }

        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        environment.snapshot = .init(changeCount: 2, containsFiles: true)
        Thread.sleep(forTimeInterval: 0.03)
        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .replaceWithMove)
        wait(for: [notReceived], timeout: 0.05)
    }

    func testGeneralCopyInvalidatesMoveWithoutRestoringMoveIntent() {
        let environment = FakeFinderEnvironment()
        let controller = makeController(environment)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        XCTAssertEqual(controller.handle(keyCode: 8, isDown: true, isRepeat: false), .passThrough)
        environment.snapshot = .init(changeCount: 2, containsFiles: true)
        Thread.sleep(forTimeInterval: 0.03)

        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .passThrough)
    }

    func testSecondCutIsConsumedWhileFirstCopyIsPending() {
        let environment = FakeFinderEnvironment()
        let controller = makeController(environment)

        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: false, isRepeat: false), .replaceWithCopy)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .consume)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: false, isRepeat: false), .consume)
    }

    func testInvalidatedPendingStillOwnsSlotUntilItsPollCompletes() {
        let environment = FakeFinderEnvironment()
        let controller = makeController(environment)

        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: false, isRepeat: false), .replaceWithCopy)
        XCTAssertEqual(controller.handle(keyCode: 8, isDown: true, isRepeat: false), .passThrough)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .consume)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: false, isRepeat: false), .consume)
    }

    func testUnknownFocusPassesCutThroughAndClearsArmedState() {
        let environment = FakeFinderEnvironment()
        let controller = makeController(environment)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        environment.snapshot = .init(changeCount: 2, containsFiles: true)
        Thread.sleep(forTimeInterval: 0.03)

        environment.context = nil
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .passThrough)
        environment.context = .init(processIdentifier: 42, windowIdentifier: 7)
        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .passThrough)
    }

    func testContextChangeWhilePendingPreventsRegistrationAfterFocusReturns() {
        let environment = FakeFinderEnvironment()
        let controller = makeController(environment)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)

        environment.context = .init(processIdentifier: 42, windowIdentifier: 8)
        environment.snapshot = .init(changeCount: 2, containsFiles: true)
        Thread.sleep(forTimeInterval: 0.03)
        environment.context = .init(processIdentifier: 42, windowIdentifier: 7)

        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .passThrough)
    }

    func testTapDisableClearsPendingArmedAndKeyOwnership() {
        let environment = FakeFinderEnvironment()
        let controller = makeController(environment)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        controller.resetAfterTapDisable()

        environment.snapshot = .init(changeCount: 2, containsFiles: true)
        Thread.sleep(forTimeInterval: 0.03)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: false, isRepeat: false), .passThrough)
        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .passThrough)
    }

    func testDeferredMoveCreationFailureKeepsArmedStateForNextPaste() {
        let environment = FakeFinderEnvironment()
        environment.deferredMoveSucceeds = false
        let controller = makeController(environment)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .consume)
        environment.snapshot = .init(changeCount: 2, containsFiles: true)
        Thread.sleep(forTimeInterval: 0.03)

        XCTAssertEqual(controller.handle(keyCode: 9, isDown: false, isRepeat: false), .consume)
        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .replaceWithMove)
    }

    func testPasteInDifferentFinderFileListIsConsumedAndCancelsPending() {
        let environment = FakeFinderEnvironment()
        let controller = makeController(environment)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        environment.context = .init(processIdentifier: 42, windowIdentifier: 8)

        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .consume)
        XCTAssertEqual(controller.handle(keyCode: 9, isDown: false, isRepeat: false), .consume)
        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .passThrough)
    }

    func testPasteOutsideFinderFileListPassesThroughWhileInvalidatingPending() {
        let environment = FakeFinderEnvironment()
        let controller = makeController(environment)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        environment.context = nil

        XCTAssertEqual(controller.handle(keyCode: 9, isDown: true, isRepeat: false), .passThrough)
    }

    private func makeController(
        _ environment: FakeFinderEnvironment,
        feedbackHandler: @escaping @Sendable (FinderFeedback) -> Void = { _ in }
    ) -> FinderCutPasteController {
        let controller = FinderCutPasteController(
            environment: environment,
            queue: DispatchQueue(label: "FinderCutPasteControllerTests"),
            pollingInterval: 0.001,
            pollingAttempts: 20,
            feedbackHandler: feedbackHandler
        )
        controller.setEnabled(true)
        return controller
    }
}
