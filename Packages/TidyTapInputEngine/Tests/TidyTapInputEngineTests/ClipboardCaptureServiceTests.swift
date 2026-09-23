import AppKit
import XCTest
@testable import TidyTapInputEngine

@MainActor
final class ClipboardCaptureServiceTests: XCTestCase {
    func testCopiesAfterActivationReachStoreAndStopPreventsFurtherCopies() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-capture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardHistoryStore(
            directory: directory, retention: 600,
            maximumEntries: 10, maximumBytes: 4096, maximumItemBytes: 2048
        )
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var failures = 0
        var notifications = 0
        let service = ClipboardCaptureService(
            store: store,
            pasteboard: board,
            onCaptured: { _ in notifications += 1 },
            onFailure: { _ in failures += 1 }
        )

        XCTAssertTrue(board.setString("before", forType: .string))
        service.start()
        board.clearContents()
        XCTAssertTrue(board.setString("after", forType: .string))
        service.poll()
        XCTAssertEqual(try store.entries().map(\.content), [.text(plain: "after", rtf: nil, html: nil)])
        XCTAssertEqual(notifications, 1)

        service.stop()
        board.clearContents()
        XCTAssertTrue(board.setString("later", forType: .string))
        service.poll()
        XCTAssertEqual(try store.entries().count, 1)
        XCTAssertEqual(failures, 0)
        XCTAssertEqual(notifications, 1)
    }

    func testStorageFailureStopsCaptureInsteadOfRepeatedlyRetrying() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-capture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardHistoryStore(
            directory: directory, retention: 600,
            maximumEntries: 10, maximumBytes: 4096, maximumItemBytes: 2048
        )
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var failures = 0
        let service = ClipboardCaptureService(store: store, pasteboard: board) { _ in failures += 1 }

        service.start()
        try FileManager.default.removeItem(at: directory)
        board.clearContents()
        XCTAssertTrue(board.setString("first", forType: .string))
        service.poll()
        XCTAssertEqual(failures, 1)
        board.clearContents()
        XCTAssertTrue(board.setString("later", forType: .string))
        service.poll()
        XCTAssertEqual(failures, 1)
    }

    func testOversizedItemIsSkippedWithoutStoppingLaterCopies() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-capture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try ClipboardHistoryStore(
            directory: directory, retention: 600,
            maximumEntries: 10, maximumBytes: 1024, maximumItemBytes: 512
        )
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        var failures = 0
        let service = ClipboardCaptureService(store: store, pasteboard: board) { _ in failures += 1 }
        service.start()
        board.clearContents()
        XCTAssertTrue(board.setString(String(repeating: "x", count: 1000), forType: .string))
        service.poll()
        XCTAssertEqual(store.oversizedCopyChangeCount(), board.changeCount)
        board.clearContents()
        XCTAssertTrue(board.setString("small", forType: .string))
        service.poll()
        XCTAssertEqual(try store.entries().map(\.content), [.text(plain: "small", rtf: nil, html: nil)])
        XCTAssertNil(store.oversizedCopyChangeCount())
        XCTAssertEqual(failures, 0)
        service.stop()
    }

    func testRichTextAndImageSurviveCaptureStoreAndPasteRepresentations() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-capture-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = NSPasteboard.withUniqueName()
        let destination = NSPasteboard.withUniqueName()
        defer {
            source.releaseGlobally()
            destination.releaseGlobally()
        }
        let store = try ClipboardHistoryStore(
            directory: directory, retention: 600,
            maximumEntries: 10, maximumBytes: 4096, maximumItemBytes: 2048
        )
        let service = ClipboardCaptureService(store: store, pasteboard: source) { error in
            XCTFail("Unexpected capture failure: \(error)")
        }
        service.start()
        source.clearContents()

        let original = NSAttributedString(
            string: "Bold\nLine",
            attributes: [
                .font: NSFont.boldSystemFont(ofSize: 18),
                .foregroundColor: NSColor.red
            ]
        )
        let rtf = try original.data(
            from: NSRange(location: 0, length: original.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
        let html = Data("<b>Bold</b><br>Line".utf8)
        let rich = NSPasteboardItem()
        XCTAssertTrue(rich.setString(original.string, forType: .string))
        XCTAssertTrue(rich.setData(rtf, forType: .rtf))
        XCTAssertTrue(rich.setData(html, forType: .html))
        XCTAssertTrue(source.writeObjects([rich]))
        service.poll()

        let reopened = try ClipboardHistoryStore(
            directory: directory, retention: 600,
            maximumEntries: 10, maximumBytes: 4096, maximumItemBytes: 2048
        )
        let savedText = try XCTUnwrap(reopened.entries().first)
        XCTAssertTrue(ClipboardPasteboardWriter.write(savedText.content, style: .plain, to: destination))
        XCTAssertEqual(destination.string(forType: .string), original.string)
        XCTAssertNil(destination.data(forType: .rtf))
        XCTAssertTrue(ClipboardPasteboardWriter.write(savedText.content, style: .formatted, to: destination))
        XCTAssertEqual(destination.data(forType: .rtf), rtf)
        XCTAssertEqual(destination.data(forType: .html), html)
        let rendered = try NSAttributedString(
            data: XCTUnwrap(destination.data(forType: .rtf)),
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        )
        XCTAssertEqual(rendered.string, original.string)
        let font = try XCTUnwrap(rendered.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
        let color = try XCTUnwrap(rendered.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor)
            .usingColorSpace(.deviceRGB)
        XCTAssertGreaterThan(try XCTUnwrap(color).redComponent, 0.8)

        let png = try XCTUnwrap(Data(base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aJX8AAAAASUVORK5CYII="))
        source.clearContents()
        let image = NSPasteboardItem()
        XCTAssertTrue(image.setData(png, forType: .png))
        XCTAssertTrue(source.writeObjects([image]))
        service.poll()
        let savedImage = try XCTUnwrap(reopened.entries().first)
        XCTAssertTrue(ClipboardPasteboardWriter.write(savedImage.content, style: .plain, to: destination))
        XCTAssertEqual(destination.data(forType: .png), png)
        XCTAssertNil(destination.string(forType: .string))
        let renderedImage = try XCTUnwrap(NSImage(data: XCTUnwrap(destination.data(forType: .png))))
        XCTAssertEqual(renderedImage.size.width, 1)
        XCTAssertEqual(renderedImage.size.height, 1)
        XCTAssertEqual(try reopened.entries().count, 2)
        service.stop()
    }
}
