import CloudKit
import CoreData
import Foundation

// SDK 콜백과 MainActor 종료 검사를 같은 잠금으로 보호한다.
final class ClipboardMirrorEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var active = Set<UUID>()
    func update(_ id: UUID, finished: Bool) {
        lock.lock(); defer { lock.unlock() }
        if finished { active.remove(id) } else { active.insert(id) }
    }
    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return active.isEmpty }
}

@MainActor
public protocol ClipboardLibraryMirroring: AnyObject {
    func start(directory: URL, containerIdentifier: String, onChange: @escaping @MainActor () -> Void,
               onFailure: @escaping @MainActor (Int) -> Void) throws
    func stop() async throws
}

@MainActor
public final class ClipboardLibraryMirror: ClipboardLibraryMirroring {
    public enum MirrorError: Error { case busy, stopIncomplete, testing }
    private var container: NSPersistentCloudKitContainer?
    private weak var retiring: NSPersistentCloudKitContainer?
    private var observers = [NSObjectProtocol]()
    private var runID: UUID?
    private let events = ClipboardMirrorEvents()

    public init() { }

    public func start(directory: URL, containerIdentifier: String, onChange: @escaping @MainActor () -> Void,
                      onFailure: @escaping @MainActor (Int) -> Void) throws {
        guard NSClassFromString("XCTestCase") == nil,
              ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil,
              ProcessInfo.processInfo.environment["TIDYTAP_LAUNCH_SMOKE"] != "1" else { throw MirrorError.testing }
        guard container == nil, retiring == nil, events.isEmpty else { throw MirrorError.busy }
        let storeURL = directory.appendingPathComponent(ClipboardLibraryStore.fileName)
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(ofType: NSSQLiteStoreType, at: storeURL, options: nil)
        guard let storeIdentifier = metadata[NSStoreUUIDKey] as? String else { throw ClipboardLibraryStore.StoreError.invalidStore }
        let description = NSPersistentStoreDescription(url: storeURL)
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
        options.databaseScope = .private
        description.cloudKitContainerOptions = options
        let loaded = NSPersistentCloudKitContainer(name: "TidyTapClipboardLibrary", managedObjectModel: ClipboardLibraryStore.managedObjectModel())
        loaded.persistentStoreDescriptions = [description]
        let run = UUID(); runID = run
        observers.append(NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange,
            object: nil, queue: nil) { [weak self] notification in
                guard let changed = notification.userInfo?[NSPersistentStoreURLKey] as? URL,
                      changed.standardizedFileURL == storeURL.standardizedFileURL else { return }
                Task { @MainActor [weak self] in guard self?.runID == run else { return }; onChange() }
            })
        let tracker = events
        observers.append(NotificationCenter.default.addObserver(forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil, queue: nil) { [weak self] notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event, event.storeIdentifier == storeIdentifier else { return }
                tracker.update(event.identifier, finished: event.endDate != nil)
                guard event.endDate != nil, !event.succeeded else { return }
                let code = (event.error as NSError?)?.code ?? -1
                Task { @MainActor [weak self] in guard self?.runID == run else { return }; onFailure(code) }
            })
        var failure: Error?
        loaded.loadPersistentStores { _, error in failure = error }
        if let failure {
            retiring = loaded
            throw failure
        }
        loaded.viewContext.transactionAuthor = "cloud-owner"
        loaded.viewContext.undoManager = nil
        container = loaded
    }

    public func stop() async throws {
        try autoreleasepool {
            if let loaded = container {
                if loaded.viewContext.hasChanges { try loaded.viewContext.save() }
                loaded.viewContext.reset()
                for store in loaded.persistentStoreCoordinator.persistentStores { try loaded.persistentStoreCoordinator.remove(store) }
                retiring = loaded
                container = nil
            }
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 30
        while retiring != nil || !events.isEmpty {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw MirrorError.stopIncomplete }
            try await Task.sleep(for: .milliseconds(50))
        }
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll(); runID = nil
    }
}
