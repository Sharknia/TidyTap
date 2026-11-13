import CoreData
import Foundation
import TidyTapInputEngine

struct ProbeEnvelope: Codable {
    let id: UUID
    let copiedAt: Date
    let content: ClipboardCapturedContent
}

struct ProbeValue: Equatable {
    let id: UUID
    let at: Date
    let content: ClipboardCapturedContent
    let isPinned: Bool
}

@MainActor
final class ProbeStore {
    static let maximumItemBytes = 10 * 1024 * 1024
    private(set) var container: NSPersistentContainer?

    init(root: URL, author: String) throws {
        let model = NSManagedObjectModel()
        model.versionIdentifiers = ["ClipboardCloudKitProbe.v1"]
        let entity = NSEntityDescription()
        entity.name = "ProbeEntry"
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        let id = NSAttributeDescription()
        id.name = "id"
        id.attributeType = .UUIDAttributeType
        id.isOptional = true
        id.preservesValueInHistoryOnDeletion = true
        let date = NSAttributeDescription()
        date.name = "lastUsedAt"
        date.attributeType = .dateAttributeType
        date.isOptional = true
        let payload = NSAttributeDescription()
        payload.name = "payload"
        payload.attributeType = .binaryDataAttributeType
        payload.isOptional = true
        payload.allowsExternalBinaryDataStorage = true
        let pin = NSAttributeDescription()
        pin.name = "isPinned"
        pin.attributeType = .booleanAttributeType
        pin.defaultValue = false
        entity.properties = [id, date, payload, pin]
        model.entities = [entity]
        let description = NSPersistentStoreDescription(url: root.appendingPathComponent("probe.sqlite"))
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
        description.cloudKitContainerOptions = nil
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)
        let loaded = NSPersistentContainer(name: "ClipboardCloudKitProbe", managedObjectModel: model)
        loaded.persistentStoreDescriptions = [description]
        var failure: Error?
        loaded.loadPersistentStores { _, error in failure = error }
        if let failure { throw failure }
        guard loaded.persistentStoreCoordinator.persistentStores.count == 1 else { throw ProbeError.invalidStore }
        loaded.viewContext.transactionAuthor = author
        loaded.viewContext.undoManager = nil
        container = loaded
    }

    static func encodeEnvelope(_ content: ClipboardCapturedContent, id: UUID, at: Date) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(ProbeEnvelope(id: id, copiedAt: at, content: content))
    }

    func insert(_ content: ClipboardCapturedContent, id: UUID = UUID(), at: Date = Date()) throws {
        guard try Self.encodeEnvelope(content, id: id, at: at).count <= Self.maximumItemBytes else {
            throw ProbeError.itemTooLarge
        }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        let payload = try encoder.encode(content)
        try withContext { context in
            let object = NSEntityDescription.insertNewObject(forEntityName: "ProbeEntry", into: context)
            object.setValue(id, forKey: "id")
            object.setValue(at, forKey: "lastUsedAt")
            object.setValue(payload, forKey: "payload")
            object.setValue(false, forKey: "isPinned")
            try context.save()
        }
    }

    func snapshot() throws -> [ProbeValue] {
        try withContext { context in
            context.refreshAllObjects()
            return try context.fetch(NSFetchRequest<NSManagedObject>(entityName: "ProbeEntry")).map { object in
                guard let id = object.value(forKey: "id") as? UUID,
                      let date = object.value(forKey: "lastUsedAt") as? Date,
                      let payload = object.value(forKey: "payload") as? Data,
                      let pin = object.value(forKey: "isPinned") as? Bool else { throw ProbeError.invalidStore }
                let content = try PropertyListDecoder().decode(ClipboardCapturedContent.self, from: payload)
                return ProbeValue(id: id, at: date, content: content, isPinned: pin)
            }.sorted { $0.id.uuidString < $1.id.uuidString }
        }
    }

    func setPinned(_ id: UUID, desired: Bool) throws {
        try withContext { context in
            let object = try Self.find(id, in: context)
            object.setValue(desired, forKey: "isPinned")
            try context.save()
        }
    }

    func delete(_ id: UUID) throws {
        try withContext { context in
            context.delete(try Self.find(id, in: context))
            try context.save()
        }
    }

    func history(after token: NSPersistentHistoryToken? = nil) throws -> [NSPersistentHistoryTransaction] {
        try withContext { context in
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
            request.resultType = .transactionsAndChanges
            let result = try context.execute(request) as? NSPersistentHistoryResult
            guard let transactions = result?.result as? [NSPersistentHistoryTransaction] else {
                throw ProbeError.invalidStore
            }
            return transactions
        }
    }

    func storeUUID() throws -> String {
        guard let coordinator = container?.persistentStoreCoordinator,
              let store = coordinator.persistentStores.first,
              let uuid = coordinator.metadata(for: store)[NSStoreUUIDKey] as? String else {
            throw ProbeError.invalidStore
        }
        return uuid
    }

    func saveHistoryToken(_ token: NSPersistentHistoryToken, to url: URL) throws {
        try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true).write(to: url)
    }

    func readHistoryToken(from url: URL) throws -> NSPersistentHistoryToken {
        guard let token = try NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self,
                                                               from: Data(contentsOf: url)) else {
            throw ProbeError.invalidStore
        }
        return token
    }

    func close() throws {
        guard let loaded = container else { return }
        try loaded.viewContext.performAndWait {
            if loaded.viewContext.hasChanges { try loaded.viewContext.save() }
            loaded.viewContext.reset()
        }
        for store in loaded.persistentStoreCoordinator.persistentStores {
            try loaded.persistentStoreCoordinator.remove(store)
        }
        container = nil
    }

    private func withContext<T>(_ body: @Sendable (NSManagedObjectContext) throws -> T) throws -> T {
        guard let context = container?.viewContext else { throw ProbeError.invalidStore }
        return try context.performAndWait { try body(context) }
    }

    private nonisolated static func find(_ id: UUID, in context: NSManagedObjectContext) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: "ProbeEntry")
        request.predicate = NSPredicate(format: "id == %@", id as NSUUID)
        guard let object = try context.fetch(request).first else { throw ProbeError.invalidStore }
        return object
    }
}
