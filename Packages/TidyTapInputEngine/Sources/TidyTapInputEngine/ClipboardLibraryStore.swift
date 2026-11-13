import CoreData
import CryptoKit
import Darwin
import Foundation

@MainActor
public protocol ClipboardHistoryStoring: AnyObject {
    @discardableResult func add(_ content: ClipboardCapturedContent, copiedAt: Date) throws -> ClipboardHistoryEntry
    func recordOversizedCopy(changeCount: Int) throws
}

public struct ClipboardLibrarySnapshot: Equatable {
    public let entries: [ClipboardHistoryEntry]
    public let historyOrder: [UUID]
    public let pinnedOrder: [UUID]
    public init(entries: [ClipboardHistoryEntry], historyOrder: [UUID], pinnedOrder: [UUID]) {
        self.entries = entries; self.historyOrder = historyOrder; self.pinnedOrder = pinnedOrder
    }
}

@MainActor
public final class ClipboardLibraryStore: ClipboardHistoryStoring {
    public enum StoreError: Error { case invalidStore, invalidPath, missingEntry, pinLimit, staleRoute }
    public let directory: URL
    public static let fileName = "library.sqlite"
    private let container: NSPersistentContainer
    private var context: NSManagedObjectContext { container.viewContext }
    private let retention: TimeInterval
    private let maximumEntries: Int
    private let maximumBytes: Int
    private let maximumItemBytes: Int
    private struct Row { let object: NSManagedObject; let entry: ClipboardHistoryEntry; let timestamp: Date }

    public static func managedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["TidyTapClipboardLibrary.v1"]
        model.entities = ["LibraryHistory", "LibraryPin"].map { name in
            let entity = NSEntityDescription()
            entity.name = name; entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
            entity.properties = [("id", NSAttributeType.UUIDAttributeType), ("payload", .binaryDataAttributeType),
                                 ("timestamp", .dateAttributeType)].map { key, type in
                let attribute = NSAttributeDescription()
                attribute.name = key; attribute.attributeType = type; attribute.isOptional = true
                if key == "payload" { attribute.allowsExternalBinaryDataStorage = true }
                if key == "id" { attribute.preservesValueInHistoryOnDeletion = true }
                return attribute
            }
            return entity
        }
        return model
    }

    public init(directory: URL, retention: TimeInterval, maximumEntries: Int,
                maximumBytes: Int, maximumItemBytes: Int) throws {
        guard retention > 0, maximumEntries > 0, maximumBytes >= maximumItemBytes, maximumItemBytes > 0 else {
            throw ClipboardHistoryStore.StoreError.invalidPolicy
        }
        self.directory = directory; self.retention = retention; self.maximumEntries = maximumEntries
        self.maximumBytes = maximumBytes; self.maximumItemBytes = maximumItemBytes
        try Self.prepareDirectory(directory)
        try Self.secureTree(directory)
        let url = directory.appendingPathComponent(Self.fileName)
        try Self.rejectSymlink(url)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
        description.cloudKitContainerOptions = nil
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        container = NSPersistentContainer(name: "TidyTapClipboardLibrary", managedObjectModel: Self.managedObjectModel())
        container.persistentStoreDescriptions = [description]
        var failure: Error?
        container.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
        container.viewContext.transactionAuthor = "local-\(getpid())"
        container.viewContext.undoManager = nil
        try secureFiles()
    }

    public static func logicalID(for content: ClipboardCapturedContent) throws -> UUID {
        // 인코더 구현/OS 버전과 무관하게 같은 콘텐츠가 같은 ID가 되도록 길이를 명시한다.
        var hash = SHA256()
        hash.update(data: Data("TidyTap.ClipboardContent.v1".utf8))
        func field(_ value: Data?) {
            guard let value else { hash.update(data: Data([0])); return }
            hash.update(data: Data([1]))
            var size = UInt64(value.count).bigEndian
            withUnsafeBytes(of: &size) { hash.update(data: Data($0)) }
            hash.update(data: value)
        }
        switch content {
        case .text(let plain, let rtf, let html):
            hash.update(data: Data([1]))
            field(Data(plain.precomposedStringWithCanonicalMapping.utf8)); field(rtf); field(html)
        case .image(let data, let type):
            hash.update(data: Data([2])); field(Data(type.rawValue.utf8)); field(data)
        }
        let bytes = Array(hash.finalize().prefix(16))
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],
                           bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }

    @discardableResult
    public func add(_ content: ClipboardCapturedContent, copiedAt: Date = Date()) throws -> ClipboardHistoryEntry {
        let id = try Self.logicalID(for: content)
        let entry = ClipboardHistoryEntry(id: id, copiedAt: copiedAt, content: content)
        guard try encoded(entry).count <= maximumItemBytes else { throw ClipboardHistoryStore.StoreError.itemTooLarge }
        context.reset()
        let existing = try rows("LibraryHistory").filter { $0.entry.id == id }
        let at = max(copiedAt, existing.map(\.timestamp).max() ?? copiedAt)
        let result = ClipboardHistoryEntry(id: id, copiedAt: at, content: content)
        do {
            try put(result, entity: "LibraryHistory", timestamp: at, existing: existing)
            try prune(now: copiedAt)
            try commit()
            try removeMarker("last-oversized-copy")
            return result
        } catch { context.rollback(); throw error }
    }

    public func snapshot(now: Date = Date()) throws -> ClipboardLibrarySnapshot {
        context.reset()
        try prune(now: now); try commit()
        let histories = latest(try rows("LibraryHistory"))
        let pins = latest(try rows("LibraryPin"))
        let historyOrder = histories.map { $0.entry.id }
        let pinnedOrder = pins.map { $0.entry.id }
        var values = Dictionary(pins.map { ($0.entry.id, $0.entry) }, uniquingKeysWith: { first, _ in first })
        for row in histories { values[row.entry.id] = row.entry }
        return .init(entries: values.values.sorted { $0.id.uuidString < $1.id.uuidString },
                     historyOrder: historyOrder, pinnedOrder: pinnedOrder)
    }

    public func entries(now: Date = Date()) throws -> [ClipboardHistoryEntry] {
        let value = try snapshot(now: now); let map = Dictionary(uniqueKeysWithValues: value.entries.map { ($0.id, $0) })
        return value.historyOrder.compactMap { map[$0] }
    }

    public func entry(id: UUID, now: Date = Date()) throws -> ClipboardHistoryEntry? {
        try snapshot(now: now).entries.first { $0.id == id }
    }

    @discardableResult
    public func promote(_ id: UUID, at date: Date = Date()) throws -> ClipboardHistoryEntry? {
        let value = try snapshot(now: date)
        guard let existing = value.entries.first(where: { $0.id == id }) else { return nil }
        let latest = value.entries.map(\.copiedAt).max() ?? date
        return try add(existing.content, copiedAt: max(date, latest.addingTimeInterval(0.001)))
    }

    public func setPinned(_ id: UUID, pinned: Bool, at date: Date = Date()) throws {
        let value = try snapshot(now: date)
        context.reset()
        let pins = try rows("LibraryPin")
        if pinned {
            if pins.contains(where: { $0.entry.id == id }) { return }
            guard let entry = value.entries.first(where: { $0.id == id }) else { throw StoreError.missingEntry }
            let unique = latest(pins)
            let bytes = try unique.reduce(0) { try $0 + encoded($1.entry).count }
            guard unique.count < maximumEntries, try bytes + encoded(entry).count <= maximumBytes else { throw StoreError.pinLimit }
            try put(entry, entity: "LibraryPin", timestamp: date, existing: [])
        } else {
            for row in pins where row.entry.id == id { context.delete(row.object) }
        }
        do { try commit() } catch { context.rollback(); throw error }
    }

    public func delete(_ id: UUID) throws { try removeHistory(id: id) }
    public func deleteAll() throws { try removeHistory(id: nil); try removeMarker("last-oversized-copy") }

    public func recordOversizedCopy(changeCount: Int) throws {
        try Self.secureWrite(Data(String(changeCount).utf8), to: directory.appendingPathComponent("last-oversized-copy"))
    }
    public func oversizedCopyChangeCount() -> Int? {
        let url = directory.appendingPathComponent("last-oversized-copy")
        guard (try? Self.rejectSymlink(url)) != nil, let data = try? Data(contentsOf: url),
              let string = String(data: data, encoding: .utf8) else { return nil }
        return Int(string)
    }

    func importLegacy(_ entries: [ClipboardHistoryEntry]) throws {
        context.reset()
        do {
            for entry in entries {
                let id = try Self.logicalID(for: entry.content)
                let converted = ClipboardHistoryEntry(id: id, copiedAt: entry.copiedAt, content: entry.content)
                guard try encoded(converted).count <= maximumItemBytes else { throw ClipboardHistoryStore.StoreError.itemTooLarge }
                let old = try rows("LibraryHistory").filter { $0.entry.id == id }
                if old.map(\.timestamp).max().map({ $0 >= entry.copiedAt }) == true { continue }
                try put(converted, entity: "LibraryHistory", timestamp: entry.copiedAt, existing: old)
            }
            try commit()
        } catch { context.rollback(); throw error }
    }

    private func removeHistory(id: UUID?) throws {
        context.reset()
        for row in try rows("LibraryHistory") where id == nil || row.entry.id == id { context.delete(row.object) }
        do { try commit() } catch { context.rollback(); throw error }
    }

    private func rows(_ entity: String) throws -> [Row] {
        try context.fetch(NSFetchRequest<NSManagedObject>(entityName: entity)).compactMap { object in
            guard let id = object.value(forKey: "id") as? UUID,
                  let payload = object.value(forKey: "payload") as? Data,
                  let timestamp = object.value(forKey: "timestamp") as? Date else { throw StoreError.invalidStore }
            let entry = try PropertyListDecoder().decode(ClipboardHistoryEntry.self, from: payload)
            guard entry.id == id, try Self.logicalID(for: entry.content) == id else { throw StoreError.invalidStore }
            return Row(object: object, entry: entry, timestamp: timestamp)
        }
    }
    private func latest(_ rows: [Row]) -> [Row] {
        var selected = [UUID: Row]()
        for row in rows where selected[row.entry.id].map({ $0.timestamp < row.timestamp }) ?? true { selected[row.entry.id] = row }
        return selected.values.sorted { $0.timestamp == $1.timestamp ? $0.entry.id.uuidString > $1.entry.id.uuidString : $0.timestamp > $1.timestamp }
    }
    private func put(_ entry: ClipboardHistoryEntry, entity: String, timestamp: Date, existing: [Row]) throws {
        let objects = existing.isEmpty ? [NSEntityDescription.insertNewObject(forEntityName: entity, into: context)] : existing.map(\.object)
        let payload = try encoded(entry)
        for object in objects { object.setValue(entry.id, forKey: "id"); object.setValue(payload, forKey: "payload"); object.setValue(timestamp, forKey: "timestamp") }
    }
    private func encoded(_ entry: ClipboardHistoryEntry) throws -> Data {
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary; return try encoder.encode(entry)
    }
    private func prune(now: Date) throws {
        let all = try rows("LibraryHistory")
        let valid = all.filter { now.timeIntervalSince($0.timestamp) < retention }
        var allowed = Set<UUID>(); var bytes = 0
        for row in latest(valid) {
            let size = try encoded(row.entry).count
            if allowed.count < maximumEntries && bytes + size <= maximumBytes { allowed.insert(row.entry.id); bytes += size }
        }
        for row in all where !allowed.contains(row.entry.id) || now.timeIntervalSince(row.timestamp) >= retention { context.delete(row.object) }
    }
    private func commit() throws { if context.hasChanges { try context.save() }; try secureFiles() }
    private func secureFiles() throws { try Self.secureTree(directory) }
    private static func secureTree(_ directory: URL) throws {
        for url in FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey])?.allObjects as? [URL] ?? [] {
            try Self.rejectSymlink(url)
            let isDirectory = try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true
            try FileManager.default.setAttributes([.posixPermissions: isDirectory ? 0o700 : 0o600], ofItemAtPath: url.path)
        }
    }
    private func removeMarker(_ name: String) throws {
        let url = directory.appendingPathComponent(name); try Self.rejectSymlink(url)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
    static func rejectSymlink(_ url: URL) throws {
        if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true { throw StoreError.invalidPath }
    }
    static func prepareDirectory(_ url: URL) throws {
        try rejectSymlink(url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }
    static func secureWrite(_ data: Data, to url: URL) throws {
        try rejectSymlink(url)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".write-\(UUID())")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw StoreError.invalidPath }
        defer { close(fd); unlink(temporary.path) }
        guard fchmod(fd, 0o600) == 0 else { throw StoreError.invalidPath }
        try data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                guard count > 0 else { throw StoreError.invalidPath }
                offset += count
            }
        }
        guard fsync(fd) == 0, rename(temporary.path, url.path) == 0 else { throw StoreError.invalidPath }
    }
}

@MainActor
public final class ClipboardLibraryRouter: ClipboardHistoryStoring {
    public struct Route: Codable, Equatable {
        public let folder: String; public let generation: UUID
        public init(folder: String, generation: UUID) { self.folder = folder; self.generation = generation }
    }
    private struct Routing: Codable { var active: Route; var accounts: [String: String] }
    public let root: URL
    private let legacyDirectory: URL
    private let retention: TimeInterval
    private let maximumEntries: Int
    private let maximumBytes: Int
    private let maximumItemBytes: Int

    public init(root: URL, legacyDirectory: URL, retention: TimeInterval, maximumEntries: Int, maximumBytes: Int, maximumItemBytes: Int) throws {
        self.root = root; self.legacyDirectory = legacyDirectory; self.retention = retention
        self.maximumEntries = maximumEntries; self.maximumBytes = maximumBytes; self.maximumItemBytes = maximumItemBytes
        try ClipboardLibraryStore.prepareDirectory(root)
    }
    public func currentRoute() throws -> Route { try locked { try routing().active } }
    public func withStore<T>(route: Route? = nil, requireCurrent: Bool = false, _ body: (ClipboardLibraryStore) throws -> T) throws -> T {
        try locked {
            let current = try routing().active
            let selected = route ?? current
            guard !requireCurrent || selected == current else { throw ClipboardLibraryStore.StoreError.staleRoute }
            guard selected.folder == "local" || Self.validAccount(selected.folder) else { throw ClipboardLibraryStore.StoreError.invalidPath }
            let store = try makeStore(selected.folder)
            if selected.folder == "local" { try migrate(store) }
            return try body(store)
        }
    }
    public func activateAccount(_ account: String) throws -> Route {
        guard Self.validAccount(account) else { throw ClipboardLibraryStore.StoreError.invalidPath }
        return try locked {
            var state = try routing()
            let firstAccount = state.accounts.isEmpty
            if firstAccount { let local = try makeStore("local"); try migrate(local); state.accounts[account] = "local" }
            let folder = state.accounts[account] ?? account
            _ = try makeStore(folder)
            state.accounts[account] = folder
            if firstAccount || state.active.folder != folder {
                state.active = Route(folder: folder, generation: UUID())
            }
            try ClipboardLibraryStore.secureWrite(JSONEncoder().encode(state), to: root.appendingPathComponent("routing.json"))
            return state.active
        }
    }
    @discardableResult public func add(_ content: ClipboardCapturedContent, copiedAt: Date = Date()) throws -> ClipboardHistoryEntry {
        try withStore { try $0.add(content, copiedAt: copiedAt) }
    }
    public func recordOversizedCopy(changeCount: Int) throws { try withStore { try $0.recordOversizedCopy(changeCount: changeCount) } }
    private func makeStore(_ folder: String) throws -> ClipboardLibraryStore {
        guard folder == "local" || Self.validAccount(folder) else { throw ClipboardLibraryStore.StoreError.invalidPath }
        return try ClipboardLibraryStore(directory: root.appendingPathComponent(folder, isDirectory: true), retention: retention,
                                  maximumEntries: maximumEntries, maximumBytes: maximumBytes, maximumItemBytes: maximumItemBytes)
    }
    private func routing() throws -> Routing {
        let url = root.appendingPathComponent("routing.json"); try ClipboardLibraryStore.rejectSymlink(url)
        if FileManager.default.fileExists(atPath: url.path) {
            try protectPrivateFile(url)
            return try JSONDecoder().decode(Routing.self, from: Data(contentsOf: url))
        }
        let initial = Routing(active: Route(folder: "local", generation: UUID()), accounts: [:])
        try ClipboardLibraryStore.secureWrite(JSONEncoder().encode(initial), to: url)
        return initial
    }
    private func migrate(_ store: ClipboardLibraryStore) throws {
        let marker = root.appendingPathComponent("legacy-imported")
        try ClipboardLibraryStore.rejectSymlink(marker)
        if FileManager.default.fileExists(atPath: marker.path) {
            try protectPrivateFile(marker)
            guard try Data(contentsOf: marker) == Data("complete".utf8) else { throw ClipboardLibraryStore.StoreError.invalidStore }
            return
        }
        if FileManager.default.fileExists(atPath: legacyDirectory.path) {
            try ClipboardLibraryStore.rejectSymlink(legacyDirectory)
            let fd = open(legacyDirectory.appendingPathComponent("store.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard fd >= 0 else { throw ClipboardLibraryStore.StoreError.invalidPath }
            defer { close(fd) }; guard flock(fd, LOCK_EX) == 0 else { throw ClipboardLibraryStore.StoreError.invalidPath }
            defer { flock(fd, LOCK_UN) }
            let files = try FileManager.default.contentsOfDirectory(at: legacyDirectory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "clip" }
            let values = try files.map { url in
                try ClipboardLibraryStore.rejectSymlink(url)
                return try PropertyListDecoder().decode(ClipboardHistoryEntry.self, from: Data(contentsOf: url))
            }
            try store.importLegacy(values)
        }
        try ClipboardLibraryStore.secureWrite(Data("complete".utf8), to: marker)
    }
    private func protectPrivateFile(_ url: URL) throws {
        try ClipboardLibraryStore.rejectSymlink(url)
        guard try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeRegular else {
            throw ClipboardLibraryStore.StoreError.invalidPath
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    private func locked<T>(_ body: () throws -> T) throws -> T {
        let fd = open(root.appendingPathComponent("routing.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw ClipboardLibraryStore.StoreError.invalidPath }
        defer { close(fd) }; guard flock(fd, LOCK_EX) == 0 else { throw ClipboardLibraryStore.StoreError.invalidPath }
        defer { flock(fd, LOCK_UN) }; return try body()
    }
    private static func validAccount(_ value: String) -> Bool { value.count == 64 && value.allSatisfy { $0.isHexDigit && $0.isASCII } }
}

@MainActor
public final class ClipboardLibraryHandle: ClipboardHistoryStoring {
    public let router: ClipboardLibraryRouter
    public let route: ClipboardLibraryRouter.Route
    public init(router: ClipboardLibraryRouter) throws { self.router = router; route = try router.currentRoute() }
    public func snapshot(now: Date = Date()) throws -> ClipboardLibrarySnapshot { try router.withStore(route: route) { try $0.snapshot(now: now) } }
    public func entries(now: Date = Date()) throws -> [ClipboardHistoryEntry] { try router.withStore(route: route) { try $0.entries(now: now) } }
    public func entry(id: UUID, now: Date = Date()) throws -> ClipboardHistoryEntry? { try router.withStore(route: route) { try $0.entry(id: id, now: now) } }
    @discardableResult public func add(_ content: ClipboardCapturedContent, copiedAt: Date = Date()) throws -> ClipboardHistoryEntry {
        try router.withStore(route: route) { try $0.add(content, copiedAt: copiedAt) }
    }
    @discardableResult public func promote(_ id: UUID, at: Date = Date()) throws -> ClipboardHistoryEntry? { try router.withStore(route: route) { try $0.promote(id, at: at) } }
    public func setPinned(_ id: UUID, pinned: Bool, at: Date = Date()) throws { try router.withStore(route: route) { try $0.setPinned(id, pinned: pinned, at: at) } }
    public func delete(_ id: UUID) throws { try router.withStore(route: route) { try $0.delete(id) } }
    public func deleteAll() throws { try router.withStore(route: route) { try $0.deleteAll() } }
    public func recordOversizedCopy(changeCount: Int) throws { try router.withStore(route: route) { try $0.recordOversizedCopy(changeCount: changeCount) } }
    public func oversizedCopyChangeCount() -> Int? { try? router.withStore(route: route) { $0.oversizedCopyChangeCount() } }
}
