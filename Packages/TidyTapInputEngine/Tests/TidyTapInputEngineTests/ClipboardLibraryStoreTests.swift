import CoreData
import Foundation
import XCTest
@testable import TidyTapInputEngine

@MainActor
final class ClipboardLibraryStoreTests: XCTestCase {
    private var root: URL!
    private let now = Date(timeIntervalSince1970: 100_000)
    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("tidytap-library-\(UUID())")
    }
    override func tearDown() async throws { try? FileManager.default.removeItem(at: root) }
    private func store(limit: Int = 10, bytes: Int = 16_384) throws -> ClipboardLibraryStore {
        try ClipboardLibraryStore(directory: root.appendingPathComponent("data"), retention: 60,
            maximumEntries: limit, maximumBytes: bytes, maximumItemBytes: min(4096, bytes))
    }
    private func router() throws -> ClipboardLibraryRouter {
        try ClipboardLibraryRouter(root: root.appendingPathComponent("v2"), legacyDirectory: root.appendingPathComponent("legacy"),
            retention: 60, maximumEntries: 10, maximumBytes: 16_384, maximumItemBytes: 4096)
    }
    private func text(_ value: String) -> ClipboardCapturedContent { .text(plain: value, rtf: nil, html: nil) }

    func testPinSurvivesHistoryExpiryAndRemovalDoesNotReviveIt() throws {
        let library = try store()
        let a = try library.add(text("A"), copiedAt: now)
        try library.setPinned(a.id, pinned: true, at: now)
        let expired = try library.snapshot(now: now.addingTimeInterval(61))
        XCTAssertTrue(expired.historyOrder.isEmpty)
        XCTAssertEqual(expired.pinnedOrder, [a.id])
        XCTAssertEqual(expired.entries.first?.content, a.content)
        try library.setPinned(a.id, pinned: false, at: now.addingTimeInterval(62))
        XCTAssertTrue(try library.snapshot(now: now.addingTimeInterval(62)).entries.isEmpty)
    }

    func testDeleteAndClearPreservePinsAndClearOversizeMarker() throws {
        let library = try store()
        let a = try library.add(text("A"), copiedAt: now)
        try library.setPinned(a.id, pinned: true, at: now)
        try library.delete(a.id)
        XCTAssertTrue(try library.entries(now: now).isEmpty)
        XCTAssertEqual(try library.entry(id: a.id, now: now)?.content, a.content)
        _ = try library.add(text("B"), copiedAt: now)
        try library.recordOversizedCopy(changeCount: 42)
        try library.deleteAll()
        XCTAssertNil(library.oversizedCopyChangeCount())
        XCTAssertEqual(try library.snapshot(now: now).pinnedOrder, [a.id])
    }

    func testPinnedOnlyPasteRenewsHistoryWithSameID() throws {
        let library = try store()
        let a = try library.add(text("A"), copiedAt: now)
        try library.setPinned(a.id, pinned: true, at: now)
        try library.delete(a.id)
        let promoted = try XCTUnwrap(library.promote(a.id, at: now.addingTimeInterval(100)))
        XCTAssertEqual(promoted.id, a.id)
        XCTAssertEqual(promoted.content, a.content)
        XCTAssertEqual(try library.snapshot(now: now.addingTimeInterval(100)).historyOrder, [a.id])
        XCTAssertEqual(try library.snapshot(now: now.addingTimeInterval(100)).pinnedOrder, [a.id])
    }

    func testLogicalIDsDeduplicateExactFormatsAndSurviveReopen() throws {
        let library = try store()
        let a = try library.add(text("A"), copiedAt: now)
        let b = try library.add(text("A"), copiedAt: now.addingTimeInterval(1))
        XCTAssertEqual(a.id, b.id)
        let rich = try library.add(.text(plain: "A", rtf: Data([1]), html: nil), copiedAt: now)
        XCTAssertNotEqual(a.id, rich.id)
        XCTAssertEqual(try store().entries(now: now.addingTimeInterval(1)).count, 2)
        XCTAssertEqual(try store().entry(id: a.id, now: now.addingTimeInterval(1))?.copiedAt, b.copiedAt)
    }

    func testExistingHandleReadsOtherHandleWritesAndDeletes() throws {
        let first = try store(); let other = try store()
        let a = try other.add(text("A"), copiedAt: now)
        XCTAssertEqual(try first.entries(now: now).map(\.id), [a.id])
        try other.setPinned(a.id, pinned: true, at: now)
        try other.delete(a.id)
        let value = try first.snapshot(now: now)
        XCTAssertTrue(value.historyOrder.isEmpty)
        XCTAssertEqual(value.pinnedOrder, [a.id])
    }

    func testLimitEvictsHistoryWithoutEvictingPinnedPayload() throws {
        let writer = try store()
        let a = try writer.add(text("A"), copiedAt: now)
        try writer.setPinned(a.id, pinned: true, at: now)
        let b = try writer.add(text("B"), copiedAt: now.addingTimeInterval(1))
        let bounded = try store(limit: 1)
        let snapshot = try bounded.snapshot(now: now.addingTimeInterval(1))
        XCTAssertEqual(snapshot.historyOrder, [b.id])
        XCTAssertEqual(snapshot.pinnedOrder, [a.id])
        XCTAssertEqual(snapshot.entries.count, 2)
    }

    func testMergedPinOverflowIsPreservedButNewLocalPinRejected() throws {
        let writer = try store()
        var ids = [UUID]()
        for name in ["A", "B", "C"] {
            let entry = try writer.add(text(name), copiedAt: now)
            ids.append(entry.id); try writer.setPinned(entry.id, pinned: true, at: now)
        }
        let d = try writer.add(text("D"), copiedAt: now.addingTimeInterval(1))
        let bounded = try store(limit: 1)
        XCTAssertEqual(Set(try bounded.snapshot(now: now.addingTimeInterval(1)).pinnedOrder), Set(ids))
        XCTAssertNoThrow(try bounded.setPinned(ids[0], pinned: true, at: now.addingTimeInterval(1)))
        XCTAssertThrowsError(try bounded.setPinned(d.id, pinned: true, at: now.addingTimeInterval(1)))
        XCTAssertEqual(try bounded.snapshot(now: now.addingTimeInterval(1)).pinnedOrder.count, 3)
    }

    func testOversizedItemDoesNotChangeLibrary() throws {
        let library = try store()
        let a = try library.add(text("A"), copiedAt: now)
        XCTAssertThrowsError(try library.add(text(String(repeating: "x", count: 5000)), copiedAt: now))
        XCTAssertEqual(try library.entries(now: now).map(\.id), [a.id])
    }

    func testLegacyImportIsNonDestructiveAndNeverReplayedAfterDeletion() throws {
        let directory = root.appendingPathComponent("legacy")
        let legacy = try ClipboardHistoryStore(directory: directory, retention: 60,
            maximumEntries: 10, maximumBytes: 16_384, maximumItemBytes: 4096)
        _ = try legacy.add(text("A"), copiedAt: now)
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "clip" })
        let original = try Data(contentsOf: file)
        let route = try router()
        let handle = try ClipboardLibraryHandle(router: route)
        XCTAssertEqual(try handle.entries(now: now).map(\.content), [text("A")])
        try handle.deleteAll()
        XCTAssertTrue(try ClipboardLibraryHandle(router: router()).entries(now: now).isEmpty)
        XCTAssertEqual(try Data(contentsOf: file), original)
    }

    func testMalformedLegacyImportPreservesAllSourceAndCanRetry() throws {
        let directory = root.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("bad.clip")
        let original = Data("malformed".utf8); try original.write(to: file)
        let route = try router()
        XCTAssertThrowsError(try route.withStore { try $0.snapshot(now: now) })
        XCTAssertEqual(try Data(contentsOf: file), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("v2/legacy-imported").path))
    }

    func testFirstAccountClaimsSameStoreAndOtherAccountIsIsolated() throws {
        let route = try router()
        let a = try route.add(text("local"), copiedAt: now)
        let initial = try route.currentRoute()
        let accountA = String(repeating: "a", count: 64), accountB = String(repeating: "b", count: 64)
        let boundA = try route.activateAccount(accountA)
        XCTAssertEqual(boundA.folder, "local")
        XCTAssertNotEqual(boundA.generation, initial.generation)
        XCTAssertEqual(try route.withStore { try $0.entries(now: now).map(\.id) }, [a.id])
        _ = try route.activateAccount(accountB)
        XCTAssertTrue(try route.withStore { try $0.entries(now: now) }.isEmpty)
        let b = try route.add(text("B"), copiedAt: now)
        XCTAssertNotEqual(b.id, a.id)
        _ = try route.activateAccount(accountA)
        XCTAssertEqual(try route.withStore { try $0.entries(now: now).map(\.id) }, [a.id])
    }

    func testCaptureUsesNewRouteWhileOldHandleRemainsBound() throws {
        let route = try router(); let old = try ClipboardLibraryHandle(router: route)
        _ = try route.activateAccount(String(repeating: "a", count: 64))
        _ = try route.activateAccount(String(repeating: "b", count: 64))
        _ = try route.add(text("B"), copiedAt: now)
        _ = try old.add(text("A"), copiedAt: now)
        XCTAssertEqual(try route.withStore { try $0.entries(now: now).map(\.content) }, [text("B")])
        XCTAssertEqual(try old.entries(now: now).map(\.content), [text("A")])
    }

    func testAllMediaEnvelopesReopenAndUnicodeIDsPreserveOriginalPayload() throws {
        let library = try store()
        let values: [ClipboardCapturedContent] = [
            .text(plain: "rich", rtf: Data("rtf".utf8), html: Data("<b>rich</b>".utf8)),
            .image(data: Data([0x89, 0x50, 0x4e, 0x47]), type: .png),
            .image(data: Data([0x49, 0x49, 0x2a, 0]), type: .tiff)
        ]
        let entries = try values.map { try library.add($0, copiedAt: now) }
        let reopened = try store()
        for entry in entries { XCTAssertEqual(try reopened.entry(id: entry.id, now: now), entry) }
        let nfd = "e\u{301}", nfc = "\u{e9}"
        XCTAssertEqual(try ClipboardLibraryStore.logicalID(for: text(nfd)), try ClipboardLibraryStore.logicalID(for: text(nfc)))
        let original = try library.add(text(nfd), copiedAt: now)
        guard case .text(let plain, _, _) = try reopened.entry(id: original.id, now: now)?.content else { return XCTFail() }
        XCTAssertEqual(Array(plain.utf8), Array(nfd.utf8))
    }

    func testMixedLegacyFailureIsAtomicAndRetryAfterCorrectionSucceeds() throws {
        let directory = root.appendingPathComponent("legacy")
        let legacy = try ClipboardHistoryStore(directory: directory, retention: 60,
            maximumEntries: 10, maximumBytes: 16_384, maximumItemBytes: 4096)
        _ = try legacy.add(text("valid"), copiedAt: now)
        let good = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first { $0.pathExtension == "clip" })
        let original = try Data(contentsOf: good)
        let bad = directory.appendingPathComponent("bad.clip"); try Data("broken".utf8).write(to: bad)
        let route = try router()
        XCTAssertThrowsError(try route.withStore { try $0.entries(now: now) })
        let raw = try ClipboardLibraryStore(directory: root.appendingPathComponent("v2/local"), retention: 60,
            maximumEntries: 10, maximumBytes: 16_384, maximumItemBytes: 4096)
        XCTAssertTrue(try raw.entries(now: now).isEmpty)
        XCTAssertEqual(try Data(contentsOf: good), original)
        XCTAssertEqual(try Data(contentsOf: bad), Data("broken".utf8))
        try FileManager.default.removeItem(at: bad)
        XCTAssertEqual(try route.withStore { try $0.entries(now: now).map(\.content) }, [text("valid")])
    }

    func testRoutingWriteFailurePreservesPreviousRouteAndData() throws {
        let route = try router()
        _ = try route.add(text("A"), copiedAt: now)
        let previous = try route.currentRoute()
        let routingURL = route.root.appendingPathComponent("routing.json")
        let original = try Data(contentsOf: routingURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: route.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: route.root.path) }
        XCTAssertThrowsError(try route.activateAccount(String(repeating: "a", count: 64)))
        XCTAssertEqual(try Data(contentsOf: routingURL), original)
        XCTAssertEqual(try route.currentRoute(), previous)
        XCTAssertEqual(try route.withStore { try $0.entries(now: now).map(\.content) }, [text("A")])
    }

    func testMarkerWriteFailureAfterSaveRetriesWithoutDuplicates() throws {
        let directory = root.appendingPathComponent("legacy")
        let legacy = try ClipboardHistoryStore(directory: directory, retention: 60,
            maximumEntries: 10, maximumBytes: 16_384, maximumItemBytes: 4096)
        _ = try legacy.add(text("A"), copiedAt: now)
        let route = try router(); _ = try route.currentRoute()
        _ = try ClipboardLibraryStore(directory: route.root.appendingPathComponent("local"), retention: 60,
            maximumEntries: 10, maximumBytes: 16_384, maximumItemBytes: 4096)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: route.root.path)
        XCTAssertThrowsError(try route.withStore { try $0.entries(now: now) })
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: route.root.path)
        XCTAssertEqual(try route.withStore { try $0.entries(now: now).count }, 1)
        XCTAssertEqual(try route.withStore { try $0.entries(now: now).count }, 1)
    }

    func testStoreTreeSymlinkRejectedBeforeLoadingAndPermissionsCorrected() throws {
        _ = try store()
        let directory = root.appendingPathComponent("data")
        let external = root.appendingPathComponent("external"); try Data("private".utf8).write(to: external)
        let link = directory.appendingPathComponent("injected-wal")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: external)
        XCTAssertThrowsError(try store())
        XCTAssertEqual(try Data(contentsOf: external), Data("private".utf8))
        try FileManager.default.removeItem(at: link)
        let sqlite = directory.appendingPathComponent("library.sqlite")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: sqlite.path)
        _ = try store()
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: sqlite.path)[.posixPermissions] as? Int, 0o600)
        XCTAssertEqual(try FileManager.default.attributesOfItem(atPath: directory.path)[.posixPermissions] as? Int, 0o700)
    }
    func testMissingRequiredFieldsRejectSnapshotInsteadOfLookingEmpty() throws {
        let library = try store()
        let container = NSPersistentContainer(name: "raw", managedObjectModel: ClipboardLibraryStore.managedObjectModel())
        let description = NSPersistentStoreDescription(url: root.appendingPathComponent("data/library.sqlite"))
        description.shouldAddStoreAsynchronously = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        container.persistentStoreDescriptions = [description]
        var failure: Error?; container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
        for field in ["id", "payload", "timestamp"] {
            let object = NSEntityDescription.insertNewObject(forEntityName: "LibraryHistory", into: container.viewContext)
            let content = text("raw")
            let id = try ClipboardLibraryStore.logicalID(for: content)
            let data = try PropertyListEncoder().encode(ClipboardHistoryEntry(id: id, copiedAt: now, content: content))
            object.setValue(id, forKey: "id"); object.setValue(data, forKey: "payload"); object.setValue(now, forKey: "timestamp")
            object.setValue(nil, forKey: field); try container.viewContext.save()
            XCTAssertThrowsError(try library.snapshot(now: now), "missing \(field)")
            container.viewContext.delete(object); try container.viewContext.save()
        }
    }

    func testMirrorEventTrackingNeedsEveryStartedEventToFinish() {
        let events = ClipboardMirrorEvents(), a = UUID(), b = UUID()
        events.update(a, finished: false); events.update(a, finished: false)
        events.update(b, finished: false); XCTAssertFalse(events.isEmpty)
        events.update(a, finished: true); XCTAssertFalse(events.isEmpty)
        events.update(b, finished: true); XCTAssertTrue(events.isEmpty)
    }

    func testContentIdentityHasVersionedCrossPlatformGoldenVector() throws {
        XCTAssertEqual(try ClipboardLibraryStore.logicalID(for: text("A")).uuidString, "469C3441-5C9D-881F-7FB3-3D3FDAFFF280")
        XCTAssertNotEqual(try ClipboardLibraryStore.logicalID(for: text("A")),
            try ClipboardLibraryStore.logicalID(for: .text(plain: "A", rtf: Data(), html: nil)))
    }

}
