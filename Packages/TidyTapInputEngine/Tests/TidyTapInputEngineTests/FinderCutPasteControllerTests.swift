import Foundation
import XCTest
@testable import TidyTapInputEngine

private final class FakeFinderEnvironment: FinderCutPasteEnvironment, @unchecked Sendable {
    private let lock = NSLock()
    private var storedContext: FinderContext? = .init(processIdentifier: 42, windowIdentifier: 7)
    private var storedSnapshot = FinderPasteboardSnapshot(changeCount: 1, containsFiles: true)
    var onDeferredMove: (() -> Void)?
    var deferredMoveSucceeds = true

    var context: FinderContext? {
        get { withLock { storedContext } }
        set { withLock { storedContext = newValue } }
    }

    var snapshot: FinderPasteboardSnapshot {
        get { withLock { storedSnapshot } }
        set { withLock { storedSnapshot = newValue } }
    }

    func focusedFileListContext() -> FinderContext? { context }
    func pasteboardSnapshot() -> FinderPasteboardSnapshot { snapshot }
    func sendDeferredMove() -> Bool {
        onDeferredMove?()
        return deferredMoveSucceeds
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

    func testSecondCutIsConsumedWhileFirstCopyIsPending() {
        let environment = FakeFinderEnvironment()
        let controller = makeController(environment)

        XCTAssertEqual(controller.handle(keyCode: 7, isDown: true, isRepeat: false), .replaceWithCopy)
        XCTAssertEqual(controller.handle(keyCode: 7, isDown: false, isRepeat: false), .replaceWithCopy)
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

    private func makeController(_ environment: FakeFinderEnvironment) -> FinderCutPasteController {
        let controller = FinderCutPasteController(
            environment: environment,
            queue: DispatchQueue(label: "FinderCutPasteControllerTests"),
            pollingInterval: 0.001,
            pollingAttempts: 20
        )
        controller.setEnabled(true)
        return controller
    }
}
