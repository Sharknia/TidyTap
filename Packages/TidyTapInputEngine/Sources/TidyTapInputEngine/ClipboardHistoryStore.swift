import Darwin
import Foundation

public struct ClipboardHistoryEntry: Codable, Equatable {
    public let id: UUID
    public let copiedAt: Date
    public let content: ClipboardCapturedContent
}

/// A bounded, user-only local store. Each copy is one atomic file; the same
/// directory lock protects reads and deletes from the app and the helper.
@MainActor
public final class ClipboardHistoryStore {
    public enum StoreError: Error {
        case itemTooLarge
        case invalidPolicy
    }

    private let directory: URL
    private let retention: TimeInterval
    private let maximumEntries: Int
    private let maximumBytes: Int
    private let maximumItemBytes: Int
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()
    private var oversizedMarkerURL: URL { directory.appendingPathComponent("last-oversized-copy") }

    public init(
        directory: URL,
        retention: TimeInterval,
        maximumEntries: Int,
        maximumBytes: Int,
        maximumItemBytes: Int
    ) throws {
        guard retention > 0, maximumEntries > 0, maximumBytes > 0,
              maximumItemBytes > 0, maximumItemBytes <= maximumBytes else {
            throw StoreError.invalidPolicy
        }
        self.directory = directory
        self.retention = retention
        self.maximumEntries = maximumEntries
        self.maximumBytes = maximumBytes
        self.maximumItemBytes = maximumItemBytes
        encoder.outputFormat = .binary
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
    }

    @discardableResult
    public func add(_ content: ClipboardCapturedContent, copiedAt: Date = Date()) throws -> ClipboardHistoryEntry {
        let entry = ClipboardHistoryEntry(id: UUID(), copiedAt: copiedAt, content: content)
        let data = try encoder.encode(entry)
        guard data.count <= maximumItemBytes else { throw StoreError.itemTooLarge }
        try withLock {
            let name = String(format: "%013lld-%@.clip", Int64(copiedAt.timeIntervalSince1970 * 1000), entry.id.uuidString)
            try writeSecurely(data, to: directory.appendingPathComponent(name))
            try prune(now: copiedAt)
            if FileManager.default.fileExists(atPath: oversizedMarkerURL.path) {
                try? FileManager.default.removeItem(at: oversizedMarkerURL)
            }
        }
        return entry
    }

    public func recordOversizedCopy(changeCount: Int) throws {
        try withLock {
            try writeSecurely(Data(String(changeCount).utf8), to: oversizedMarkerURL)
        }
    }

    public func oversizedCopyChangeCount() -> Int? {
        guard let data = try? Data(contentsOf: oversizedMarkerURL),
              let value = String(data: data, encoding: .utf8) else { return nil }
        return Int(value)
    }

    public func entries(now: Date = Date()) throws -> [ClipboardHistoryEntry] {
        try withLock {
            try prune(now: now)
            return try readEntries().map(\.entry).sorted {
                $0.copiedAt == $1.copiedAt ? $0.id.uuidString > $1.id.uuidString : $0.copiedAt > $1.copiedAt
            }
        }
    }

    public func delete(_ id: UUID) throws {
        try withLock {
            for file in try itemFiles() where file.lastPathComponent.hasSuffix("-\(id.uuidString).clip") {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    public func deleteAll() throws {
        try withLock {
            for file in try itemFiles() {
                try FileManager.default.removeItem(at: file)
            }
            if FileManager.default.fileExists(atPath: oversizedMarkerURL.path) {
                try FileManager.default.removeItem(at: oversizedMarkerURL)
            }
        }
    }

    private func prune(now: Date) throws {
        var items = try readEntries().sorted { $0.entry.copiedAt > $1.entry.copiedAt }
        for item in items where now.timeIntervalSince(item.entry.copiedAt) >= retention {
            try FileManager.default.removeItem(at: item.url)
        }
        items.removeAll { now.timeIntervalSince($0.entry.copiedAt) >= retention }
        var seen = Set<ClipboardCapturedContent>()
        var unique = [(entry: ClipboardHistoryEntry, url: URL, bytes: Int)]()
        for item in items {
            if seen.insert(item.entry.content).inserted {
                unique.append(item)
            } else {
                try FileManager.default.removeItem(at: item.url)
            }
        }
        items = unique
        var total = items.reduce(0) { $0 + $1.bytes }
        while items.count > maximumEntries || total > maximumBytes {
            let oldest = items.removeLast()
            try FileManager.default.removeItem(at: oldest.url)
            total -= oldest.bytes
        }
    }

    private func readEntries() throws -> [(entry: ClipboardHistoryEntry, url: URL, bytes: Int)] {
        try itemFiles().compactMap { url in
            let data = try Data(contentsOf: url)
            guard let entry = try? decoder.decode(ClipboardHistoryEntry.self, from: data) else {
                try FileManager.default.removeItem(at: url)
                return nil
            }
            return (entry, url, data.count)
        }
    }

    private func itemFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "clip" }
    }

    private func withLock<T>(_ operation: () throws -> T) throws -> T {
        let descriptor = open(directory.appendingPathComponent("store.lock").path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX) == 0 else { throw posixError() }
        defer { flock(descriptor, LOCK_UN) }
        for pending in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            where pending.lastPathComponent.hasPrefix(".pending-") {
            try FileManager.default.removeItem(at: pending)
        }
        return try operation()
    }

    private func writeSecurely(_ data: Data, to destination: URL) throws {
        let temporary = directory.appendingPathComponent(".pending-\(UUID().uuidString)")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw posixError() }
        var committed = false
        defer {
            close(descriptor)
            if !committed { unlink(temporary.path) }
        }
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                guard count > 0 else { throw posixError() }
                offset += count
            }
        }
        guard fsync(descriptor) == 0, rename(temporary.path, destination.path) == 0 else {
            throw posixError()
        }
        committed = true
    }

    private func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
    }
}
