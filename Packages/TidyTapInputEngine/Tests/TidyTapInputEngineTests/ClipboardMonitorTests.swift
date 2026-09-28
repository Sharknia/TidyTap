import AppKit
import XCTest
@testable import TidyTapInputEngine

@MainActor
final class ClipboardMonitorTests: XCTestCase {
    func testStartsAfterExistingCopyAndStopsCollectingWhenDisabled() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        XCTAssertTrue(board.setString("before enable", forType: .string))
        var captured = [ClipboardCapture]()
        let monitor = ClipboardMonitor(pasteboard: board) { captured.append($0) }

        monitor.start()
        monitor.poll()
        XCTAssertTrue(captured.isEmpty)

        board.clearContents()
        XCTAssertTrue(board.setString("A", forType: .string))
        monitor.poll()
        XCTAssertEqual(captured.map(\.content), [.text(plain: "A", rtf: nil, html: nil)])

        board.clearContents()
        XCTAssertTrue(board.setString("B", forType: .string))
        monitor.poll()
        XCTAssertEqual(captured.map(\.content), [
            .text(plain: "A", rtf: nil, html: nil),
            .text(plain: "B", rtf: nil, html: nil)
        ])

        monitor.stop()
        board.clearContents()
        XCTAssertTrue(board.setString("after disable", forType: .string))
        monitor.poll()
        XCTAssertEqual(captured.count, 2)
    }

    func testReadDenialStopsWithoutRepeatedAttempts() {
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var readAllowed = true
        var denied = 0
        var captured = 0
        let monitor = ClipboardMonitor(
            pasteboard: board,
            canRead: { readAllowed },
            onReadDenied: { denied += 1 },
            onCapture: { _ in captured += 1 }
        )
        monitor.start()
        monitor.poll()
        XCTAssertEqual(denied, 0)
        readAllowed = false
        monitor.poll()
        monitor.poll()
        XCTAssertEqual(denied, 1)
        XCTAssertEqual(captured, 0)
        readAllowed = true
        board.clearContents()
        XCTAssertTrue(board.setString("B", forType: .string))
        monitor.poll()
        XCTAssertEqual(captured, 0)
    }
}
