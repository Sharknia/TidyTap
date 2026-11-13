import AppKit
import CoreData
import Darwin
import Foundation
import TidyTapInputEngine

private final class ProbeNotificationCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    private var tokens = [NSPersistentHistoryToken]()
    func increment(token: NSPersistentHistoryToken?) {
        lock.lock()
        value += 1
        if let token { tokens.append(token) }
        lock.unlock()
    }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
    func contains(_ token: NSPersistentHistoryToken) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return tokens.contains { $0.isEqual(token) }
    }
}

@MainActor
enum ProbeScenario {
    struct Result: Codable {
        let id: String
        var status: String
    }
    struct Report: Codable {
        let scope: String
        let runID: UUID
        let os: String
        let results: [Result]
        let measurements: [String: Int]
    }

    static func run(_ run: ProbeRun) throws {
        var results = (1...9).map { Result(id: String(format: "L%02d", $0), status: "not_run") }
        var measurements = [String: Int]()
        var store = try ProbeStore(root: run.root, author: "local-owner")
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)
        var fixtureValues = [ProbeValue]()

        func record() throws {
            let report = Report(scope: "local-only; CloudKit not run", runID: run.id,
                                os: ProcessInfo.processInfo.operatingSystemVersionString, results: results, measurements: measurements)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(report).write(to: run.root.appendingPathComponent("results.json"), options: .atomic)
        }

        func test(_ index: Int, body: () throws -> Void) throws {
            let started = ProcessInfo.processInfo.systemUptime
            do {
                try body()
                measurements["L\(String(format: "%02d", index))-milliseconds"] = Int((ProcessInfo.processInfo.systemUptime - started) * 1000)
                results[index - 1].status = "passed"
                try record()
                print("\(results[index - 1].id): passed (local)")
            } catch {
                results[index - 1].status = "failed"
                try? record()
                throw error
            }
        }

        try record()
        try test(1) {
            let image = try makeImages()
            let contents: [ClipboardCapturedContent] = [
                .text(plain: "합성 텍스트", rtf: nil, html: nil),
                .text(plain: "synthetic", rtf: Data("{\\rtf1 synthetic}".utf8),
                      html: Data("<b>synthetic</b>".utf8)),
                .image(data: image.png, type: .png), .image(data: image.tiff, type: .tiff),
                .image(data: Data(repeating: 0x5a, count: 2 * 1024 * 1024), type: .png)
            ]
            measurements["format-cases"] = contents.count
            for (offset, content) in contents.enumerated() {
                let id = UUID()
                let at = fixedDate.addingTimeInterval(Double(offset))
                let envelope = try ProbeStore.encodeEnvelope(content, id: id, at: at)
                let legacy = try PropertyListDecoder().decode(ClipboardHistoryEntry.self, from: envelope)
                try expect(legacy.id == id && legacy.copiedAt == at && legacy.content == content, "L01-codec")
                try store.insert(content, id: id, at: at)
                fixtureValues.append(ProbeValue(id: id, at: at, content: content, isPinned: false))
            }
            try expect(try store.snapshot() == fixtureValues.sorted { $0.id.uuidString < $1.id.uuidString }, "L01-values")
        }

        try test(2) {
            try store.setPinned(fixtureValues[0].id, desired: true)
            let values = try store.snapshot()
            let uuid = try store.storeUUID()
            let historyCount = try store.history().count
            measurements["reopen-count"] = 3
            for _ in 0..<3 {
                try store.close()
                store = try ProbeStore(root: run.root, author: "local-owner")
                try expect(try store.storeUUID() == uuid, "L02-uuid")
                try expect(try store.snapshot() == values, "L02-values")
                try expect(try store.history().count == historyCount, "L02-history")
            }
        }

        try test(3) {
            let id = UUID()
            try store.insert(.text(plain: "synthetic-history", rtf: nil, html: nil), id: id, at: fixedDate)
            guard let initial = try store.history().last,
                  let inserted = initial.changes?.first, inserted.changeType == .insert else {
                throw ProbeError.assertion("L03-insert")
            }
            let objectURI = inserted.changedObjectID.uriRepresentation()
            let tokenURL = run.root.appendingPathComponent("history-token.bin")
            try store.saveHistoryToken(initial.token, to: tokenURL)
            try store.setPinned(id, desired: true)
            try store.delete(id)
            try store.close()
            store = try ProbeStore(root: run.root, author: "local-owner")
            let token = try store.readHistoryToken(from: tokenURL)
            let transactions = try store.history(after: token)
            let changes = transactions.flatMap { $0.changes ?? [] }
                .filter { $0.changedObjectID.uriRepresentation() == objectURI }
            try expect(changes.count == 2 && changes.contains { $0.changeType == .update }
                       && changes.contains { $0.changeType == .delete }
                       && !changes.contains { $0.changeType == .insert }, "L03-window")
            try expect(changes.first { $0.changeType == .delete }?.tombstone?["id"] as? UUID == id,
                       "L03-delete-id")
            try expect(transactions.allSatisfy { $0.author == "local-owner" }, "L03-author")
        }

        try test(4) {
            let id = UUID()
            try store.close()
            store = try ProbeStore(root: run.root, author: "local-owner")
            try store.insert(.text(plain: "synthetic-X", rtf: nil, html: nil), id: id, at: fixedDate)
            try store.setPinned(id, desired: true)
            try store.setPinned(id, desired: false)
            try store.delete(fixtureValues[1].id)
            let uuid = try store.storeUUID()
            try store.close()
            store = try ProbeStore(root: run.root, author: "local-owner")
            let values = try store.snapshot()
            try expect(try store.storeUUID() == uuid, "L04-uuid")
            let expected = ProbeValue(id: id, at: fixedDate,
                content: .text(plain: "synthetic-X", rtf: nil, html: nil), isPinned: false)
            try expect(values.first { $0.id == id } == expected, "L04-X")
            try expect(!values.contains { $0.id == fixtureValues[1].id }, "L04-H")
            try expect(try store.history().flatMap { $0.changes ?? [] }.contains {
                $0.changeType == .delete && $0.tombstone?["id"] as? UUID == fixtureValues[1].id
            }, "L04-history")
        }

        try test(5) {
            let id = UUID()
            let limit = ProbeStore.maximumItemBytes
            measurements["accepted-envelope-bytes"] = limit
            measurements["rejected-envelope-bytes"] = limit + 1
            var byteCount = limit - 1024
            for _ in 0..<4 {
                let content = ClipboardCapturedContent.image(data: Data(repeating: 0x6b, count: byteCount), type: .png)
                byteCount += limit - (try ProbeStore.encodeEnvelope(content, id: id, at: fixedDate).count)
            }
            let boundary = ClipboardCapturedContent.image(data: Data(repeating: 0x6b, count: byteCount), type: .png)
            try expect(try ProbeStore.encodeEnvelope(boundary, id: id, at: fixedDate).count == limit, "L05-exact")
            try store.insert(boundary, id: id, at: fixedDate)
            try expect(try store.snapshot().first { $0.id == id }?.content == boundary, "L05-read")
            let before = try store.snapshot().count
            let oversized = ClipboardCapturedContent.image(data: Data(repeating: 0x6b, count: byteCount + 1), type: .png)
            try expect(try ProbeStore.encodeEnvelope(oversized, id: id, at: fixedDate).count == limit + 1, "L05-over")
            do {
                try store.insert(oversized, id: id, at: fixedDate)
                throw ProbeError.assertion("L05-rejected")
            } catch ProbeError.itemTooLarge { }
            try expect(try store.snapshot().count == before, "L05-count")
        }

        try test(6) {
            let multiRun = try ProbeRun.create(at: run.root.appendingPathComponent("multiprocess", isDirectory: true))
            let owner = try ProbeStore(root: multiRun.root, author: "local-owner")
            let uuid = try owner.storeUUID()
            let baselineID = UUID()
            try owner.insert(.text(plain: "synthetic-baseline", rtf: nil, html: nil), id: baselineID, at: fixedDate)
            guard let baseline = try owner.history().last else { throw ProbeError.assertion("L06-baseline") }
            let tokenURL = multiRun.root.appendingPathComponent("owner-token.bin")
            try owner.saveHistoryToken(baseline.token, to: tokenURL)
            let baselineURI = try owner.objectURI(for: baselineID)
            let counter = ProbeNotificationCounter()
            let observer = NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange,
                object: owner.container?.persistentStoreCoordinator, queue: nil) { notification in
                    counter.increment(token: notification.userInfo?[NSPersistentHistoryTokenKey] as? NSPersistentHistoryToken)
                }
            defer { NotificationCenter.default.removeObserver(observer) }
            let id = UUID()
            let status = try child(["writer", multiRun.root.path, multiRun.id.uuidString, id.uuidString])
            try expect(status == 0, "L06-writer")
            let transactions = try owner.history(after: owner.readHistoryToken(from: tokenURL))
            let uri = try owner.objectURI(for: id)
            try expect(transactions.count == 1 && transactions[0].author == "local-writer", "L06-author")
            let changes = transactions.flatMap { $0.changes ?? [] }
            try expect(changes.count == 1 && changes[0].changeType == .insert
                       && changes[0].changedObjectID.uriRepresentation() == uri
                       && !changes.contains { $0.changedObjectID.uriRepresentation() == baselineURI }, "L06-token-window")
            let writerToken = transactions[0].token
            let deadline = ProcessInfo.processInfo.systemUptime + 5
            while !counter.contains(writerToken) && ProcessInfo.processInfo.systemUptime < deadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
            try expect(counter.contains(writerToken), "L06-notification-token")
            measurements["writer-notifications"] = counter.count
            measurements["writer-token-consumed"] = 1
            measurements["writer-notification-token-matched"] = 1
            measurements["writer-history-transactions"] = transactions.count
            try expect(try owner.snapshot().first { $0.id == id } == writerFixture(id: id), "L06-value")
            try expect(try owner.storeUUID() == uuid, "L06-uuid")
            try owner.close()
        }

        try test(7) {
            try expect(type(of: store.container!) == NSPersistentContainer.self, "L07-type")
            try expect(store.container!.persistentStoreDescriptions.allSatisfy {
                $0.cloudKitContainerOptions == nil
            }, "L07-options")
            let rejectedRoot = run.root.appendingPathComponent("cloud-must-not-exist")
            try expect(try child(["cloud", rejectedRoot.path]) == 64, "L07-mode")
            try expect(try child(["self-test", rejectedRoot.path, "--container", "invalid"]) == 64, "L07-args")
            try expect(!FileManager.default.fileExists(atPath: rejectedRoot.path), "L07-no-store")
        }

        try test(8) {
            let brokenRoot = run.root.appendingPathComponent("broken", isDirectory: true)
            try FileManager.default.createDirectory(at: brokenRoot, withIntermediateDirectories: false,
                                                     attributes: [.posixPermissions: 0o700])
            let url = brokenRoot.appendingPathComponent("probe.sqlite")
            let original = Data("synthetic-invalid-sqlite".utf8)
            try original.write(to: url)
            var rejected = false
            do {
                let unexpected = try ProbeStore(root: brokenRoot, author: "local-owner")
                try unexpected.close()
            } catch { rejected = true }
            try expect(rejected, "L08-rejected")
            try expect(try Data(contentsOf: url) == original, "L08-preserved")
        }

        try test(9) {
            let id = UUID().uuidString
            let unmarked = run.root.appendingPathComponent("unmarked", isDirectory: true)
            try FileManager.default.createDirectory(at: unmarked, withIntermediateDirectories: false,
                                                     attributes: [.posixPermissions: 0o700])
            try expect(try child(["writer", unmarked.path, run.id.uuidString, id]) != 0, "L09-marker")
            try expect(try FileManager.default.contentsOfDirectory(atPath: unmarked.path).isEmpty, "L09-no-write")
            let before = try store.snapshot()
            let markerURL = run.root.appendingPathComponent("run-marker.json")
            let markerData = try Data(contentsOf: markerURL)
            try expect(try child(["writer", run.root.path, UUID().uuidString, id]) != 0, "L09-wrong-uuid")
            try expect(try store.snapshot() == before && Data(contentsOf: markerURL) == markerData, "L09-uuid-preserved")
            let wrongKind = run.root.appendingPathComponent("wrong-kind", isDirectory: true)
            try FileManager.default.createDirectory(at: wrongKind, withIntermediateDirectories: false,
                                                     attributes: [.posixPermissions: 0o700])
            let invalid = ProbeRun.Marker(kind: "invalid-kind", id: UUID())
            let invalidData = try JSONEncoder().encode(invalid)
            let invalidURL = wrongKind.appendingPathComponent("run-marker.json")
            try invalidData.write(to: invalidURL)
            try expect(try child(["writer", wrongKind.path, invalid.id.uuidString, id]) != 0, "L09-wrong-kind")
            try expect(try Data(contentsOf: invalidURL) == invalidData
                       && FileManager.default.contentsOfDirectory(atPath: wrongKind.path) == ["run-marker.json"],
                       "L09-kind-preserved")
            measurements["marker-rejection-cases"] = 3
            let link = run.root.appendingPathComponent("symlink-root")
            try FileManager.default.createSymbolicLink(at: link, withDestinationURL: unmarked)
            try expect(try child(["self-test", link.path]) != 0, "L09-symlink")
            try FileManager.default.removeItem(at: link)
            try expect(try child(["self-test", run.root.path]) != 0, "L09-existing-root")
            try ProbeRun.validateTree(run.root)
        }
        try store.close()
        try record()
        try ProbeRun.validateTree(run.root)
        print("local-probe: passed; CloudKit: not_run")
    }

    private static func expect(_ condition: Bool, _ id: String) throws {
        if !condition { throw ProbeError.assertion(id) }
    }

    static func writerFixture(id: UUID) -> ProbeValue {
        ProbeValue(id: id, at: Date(timeIntervalSince1970: 1_700_000_100),
                   content: .text(plain: "synthetic-writer", rtf: nil, html: nil), isPinned: false)
    }

    private static func child(_ arguments: [String]) throws -> Int32 {
        guard let executable = Bundle.main.executableURL else { throw ProbeError.invalidStore }
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + 15
        while process.isRunning && ProcessInfo.processInfo.systemUptime < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        if process.isRunning {
            process.terminate()
            let stopDeadline = ProcessInfo.processInfo.systemUptime + 1
            while process.isRunning && ProcessInfo.processInfo.systemUptime < stopDeadline { usleep(10_000) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            throw ProbeError.timedOut
        }
        process.waitUntilExit()
        return process.terminationStatus
    }

    private static func makeImages() throws -> (png: Data, tiff: Data) {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 8, bitsPerPixel: 32), let bytes = bitmap.bitmapData else {
            throw ProbeError.assertion("L01-fixture")
        }
        for offset in 0..<16 { bytes[offset] = UInt8(offset * 13) }
        guard let png = bitmap.representation(using: .png, properties: [:]),
              let tiff = bitmap.representation(using: .tiff, properties: [:]) else {
            throw ProbeError.assertion("L01-fixture")
        }
        return (png, tiff)
    }
}
