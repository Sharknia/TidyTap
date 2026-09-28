import Foundation
import XCTest
@testable import TidyTapInputEngine

@MainActor
final class ClipboardHistoryStoreTests: XCTestCase {
    func testRepeatedCopiesKeepOnlyNewestExactContent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-dedupe-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 100_000)
        let store = try ClipboardHistoryStore(
            directory: directory, retention: 600,
            maximumEntries: 10, maximumBytes: 4096, maximumItemBytes: 2048
        )
        let plain = ClipboardCapturedContent.text(plain: "same", rtf: nil, html: nil)
        let first = try store.add(plain, copiedAt: now.addingTimeInterval(-5))
        let rich = try store.add(.text(plain: "same", rtf: Data("bold".utf8), html: nil),
                                 copiedAt: now.addingTimeInterval(-4))
        let latestPlain = try store.add(plain, copiedAt: now.addingTimeInterval(-3))
        let image = ClipboardCapturedContent.image(data: Data([1, 2, 3]), type: .png)
        let firstImage = try store.add(image, copiedAt: now.addingTimeInterval(-2))
        let latestImage = try store.add(image, copiedAt: now.addingTimeInterval(-1))

        let entries = try store.entries(now: now)
        XCTAssertEqual(entries.map(\.id), [latestImage.id, latestPlain.id, rich.id])
        XCTAssertFalse(entries.contains(first))
        XCTAssertFalse(entries.contains(firstImage))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "clip" }.count, 3)
    }

    func testSuccessfulReusePromotesOneItemAndRenewsRetention() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-promote-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let now = Date(timeIntervalSince1970: 100_000)
        let store = try ClipboardHistoryStore(
            directory: directory, retention: 60,
            maximumEntries: 10, maximumBytes: 4096, maximumItemBytes: 2048
        )
        let a = try store.add(.text(plain: "A", rtf: nil, html: nil), copiedAt: now.addingTimeInterval(-50))
        let b = try store.add(.text(plain: "B", rtf: nil, html: nil), copiedAt: now.addingTimeInterval(-20))
        let c = try store.add(.text(plain: "C", rtf: nil, html: nil), copiedAt: now.addingTimeInterval(-10))
        XCTAssertEqual(try store.entries(now: now).map(\.id), [c.id, b.id, a.id])

        XCTAssertEqual(try store.promote(a.id, at: now)?.id, a.id)
        XCTAssertEqual(try store.entries(now: now).map(\.id), [a.id, c.id, b.id])
        XCTAssertGreaterThan(try XCTUnwrap(store.promote(a.id, at: now)).copiedAt, now)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "clip" }.count, 3)
        XCTAssertNil(try store.promote(UUID(), at: now))
        XCTAssertEqual(try store.entries(now: now.addingTimeInterval(59)).map(\.id), [a.id])
        XCTAssertNil(try store.promote(a.id, at: now.addingTimeInterval(61)),
                     "expired history is not revived by a late result")
    }

    func testRecordsSurviveReopenAndOldestItemsCanBeRemoved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-store-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let time = Date(timeIntervalSince1970: 100_000)
        let store = try ClipboardHistoryStore(
            directory: directory, retention: 600,
            maximumEntries: 2, maximumBytes: 4096, maximumItemBytes: 2048
        )
        let a = try store.add(.text(plain: "A", rtf: nil, html: nil), copiedAt: time.addingTimeInterval(-3))
        let b = try store.add(.text(plain: "B", rtf: nil, html: nil), copiedAt: time.addingTimeInterval(-2))
        let c = try store.add(.text(plain: "C", rtf: nil, html: nil), copiedAt: time.addingTimeInterval(-1))

        let reopened = try ClipboardHistoryStore(
            directory: directory, retention: 600,
            maximumEntries: 2, maximumBytes: 4096, maximumItemBytes: 2048
        )
        XCTAssertEqual(try reopened.entries(now: time).map(\.id), [c.id, b.id])
        XCTAssertFalse(try reopened.entries(now: time).contains(a))
        try reopened.delete(b.id)
        XCTAssertEqual(try reopened.entries(now: time).map(\.id), [c.id])
        try reopened.recordOversizedCopy(changeCount: 42)
        XCTAssertEqual(reopened.oversizedCopyChangeCount(), 42)
        try reopened.deleteAll()
        XCTAssertTrue(try reopened.entries(now: time).isEmpty)
        XCTAssertNil(reopened.oversizedCopyChangeCount())
    }

    func testExpiryAndItemLimitKeepPrivateFilesBounded() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-store-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let time = Date(timeIntervalSince1970: 100_000)
        let store = try ClipboardHistoryStore(
            directory: directory, retention: 60,
            maximumEntries: 3, maximumBytes: 1024, maximumItemBytes: 512
        )
        _ = try store.add(.text(plain: "old", rtf: nil, html: nil), copiedAt: time.addingTimeInterval(-61))
        let recent = try store.add(.text(plain: "recent", rtf: nil, html: nil), copiedAt: time.addingTimeInterval(-5))
        XCTAssertEqual(try store.entries(now: time).map(\.id), [recent.id])
        XCTAssertThrowsError(try store.add(.text(plain: String(repeating: "x", count: 1000), rtf: nil, html: nil), copiedAt: time))
        XCTAssertEqual(try store.entries(now: time).count, 1)

        let directoryMode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int)
        XCTAssertEqual(directoryMode & 0o777, 0o700)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "clip" }))
        let fileMode = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int)
        XCTAssertEqual(fileMode & 0o777, 0o600)

        let damaged = directory.appendingPathComponent("damaged.clip")
        try Data("broken".utf8).write(to: damaged)
        let orphan = directory.appendingPathComponent(".pending-orphan")
        try Data("private draft".utf8).write(to: orphan)
        XCTAssertEqual(try store.entries(now: time).count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: damaged.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
    }
}
