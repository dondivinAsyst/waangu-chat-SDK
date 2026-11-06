//
//  CoreDataEngine.swift
//  AppModules
//
//  Created by Asyst on 5/17/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/Engines/CoreDataEngine.swift             │
// │                                                              │
// │  INTERNE — sélectionné via DatabaseAssembly(.coreData).      │
// │                                                              │
// │  Stratégie de stockage :                                     │
// │    - Un NSPersistentContainer par namespace                  │
// │    - Modèle construit en mémoire (pas de .xcdatamodeld)      │
// │      → toutes les entités stockées via EntityProxy           │
// │        (entityId, entityType, namespace, jsonPayload, dates) │
// │    - WAL mode + FileProtection activés                       │
// │    - Reads sur background context (concurrent avec WAL)      │
// │    - Writes sur un context dédié sérialisé dans l'actor      │
// │    - Transactions : accumulation dans le write context       │
// │                     + rollback() sur annulation              │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import CoreData
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: CoreDataEngine
// ─────────────────────────────────────────────────────────────

actor CoreDataEngine: DatabaseEngine {

    // ── État interne ──────────────────────────────────────────
    private var stacks:        [String: NSPersistentContainer]  = [:]
    private var writeContexts: [String: NSManagedObjectContext] = [:]
    private var inTransaction: Set<String>                      = []

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    // ─────────────────────────────────────────────────────────
    // MARK: Setup
    // ─────────────────────────────────────────────────────────

    func setup(namespace: String, config: DatabaseEngineConfig) async throws {
        guard stacks[namespace] == nil else { return }

        // 1. Répertoire de stockage
        try FileManager.default.createDirectory(
            at: config.storeDirectory,
            withIntermediateDirectories: true
        )
        let storeURL = config.storeDirectory.appending(path: "\(namespace).sqlite")

        // 2. Migrations avant ouverture du container
        if !config.migrationSteps.isEmpty {
            let migrationCtx = CoreDataMigrationContext(
                namespace: namespace,
                storeURL:  storeURL
            )
            let manager = MigrationManager()
            try await manager.run(
                steps:     config.migrationSteps,
                namespace: namespace,
                storeURL:  storeURL,
                context:   migrationCtx
            )
        }

        // 3. Modèle NSManagedObjectModel construit en mémoire
        let model     = CoreDataEngine.buildModel()
        let container = NSPersistentContainer(name: namespace, managedObjectModel: model)

        // 4. Descripteur du store
        let desc = NSPersistentStoreDescription(url: storeURL)
        desc.setOption(
            ["journal_mode": "WAL"] as NSDictionary,
            forKey: NSSQLitePragmasOption
        )
        desc.setOption(
            FileProtectionType.completeUnlessOpen as NSObject,
            forKey: NSPersistentStoreFileProtectionKey
        )
        desc.shouldMigrateStoreAutomatically      = true
        desc.shouldInferMappingModelAutomatically = true
        container.persistentStoreDescriptions = [desc]

        // 5. Chargement du store
        try await withCheckedThrowingContinuation {
            (c: CheckedContinuation<Void, Error>) in
            container.loadPersistentStores { _, error in
                if let error {
                    c.resume(throwing: DatabaseError.migrationFailed(
                        namespace:   namespace,
                        fromVersion: 0,
                        toVersion:   1,
                        underlying:  error
                    ))
                } else {
                    c.resume()
                }
            }
        }

        // 6. viewContext
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        // 7. Context d'écriture dédié — sérialisé dans l'actor
        let writer = container.newBackgroundContext()
        writer.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy

        stacks[namespace]        = container
        writeContexts[namespace] = writer
    }

    func teardown(namespace: String) async throws {
        writeContexts.removeValue(forKey: namespace)
        stacks.removeValue(forKey: namespace)
        inTransaction.remove(namespace)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Contexts
    // ─────────────────────────────────────────────────────────

    private func writeContext(for namespace: String) throws -> NSManagedObjectContext {
        guard let ctx = writeContexts[namespace] else {
            throw DatabaseError.namespaceNotReady(namespace)
        }
        return ctx
    }

    /// Nouveau background context par lecture → N lectures concurrentes (WAL).
    private func readContext(for namespace: String) throws -> NSManagedObjectContext {
        guard let container = stacks[namespace] else {
            throw DatabaseError.namespaceNotReady(namespace)
        }
        let ctx = container.newBackgroundContext()
        ctx.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        return ctx
    }

    // ─────────────────────────────────────────────────────────
    // MARK: CRUD — Save
    // ─────────────────────────────────────────────────────────

    func performSave<T: Storable>(_ entity: T, namespace: String) async throws {
        let ctx  = try writeContext(for: namespace)
        let data = try encoder.encode(entity)
        try await ctx.perform {
            let proxy = try self.upsertProxy(
                id: "\(entity.id)", type: "\(T.self)",
                namespace: namespace, in: ctx
            )
            proxy.setValue(data,   forKey: Keys.jsonPayload)
            proxy.setValue(Date(), forKey: Keys.updatedAt)
            try self.saveIfNotInTransaction(ctx: ctx, namespace: namespace)
        }
    }

    func performSaveAll<T: Storable>(_ entities: [T], namespace: String) async throws {
        let ctx = try writeContext(for: namespace)
        try await ctx.perform {
            for entity in entities {
                let data  = try self.encoder.encode(entity)
                let proxy = try self.upsertProxy(
                    id: "\(entity.id)", type: "\(T.self)",
                    namespace: namespace, in: ctx
                )
                proxy.setValue(data,   forKey: Keys.jsonPayload)
                proxy.setValue(Date(), forKey: Keys.updatedAt)
            }
            try self.saveIfNotInTransaction(ctx: ctx, namespace: namespace)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: CRUD — Fetch
    // ─────────────────────────────────────────────────────────

    func performFetch<T: Storable>(
        _ type: T.Type,
        namespace: String,
        query: QuerySpec?
    ) async throws -> [T] {
        let ctx = try readContext(for: namespace)
        let req = Self.fetchRequest(entityType: "\(type)", query: query)
        return try await ctx.perform {
            let proxies = try ctx.fetch(req)
            return try proxies.compactMap { proxy -> T? in
                guard let data = proxy.value(forKey: Keys.jsonPayload) as? Data else {
                    return nil
                }
                do {
                    return try self.decoder.decode(type, from: data)
                } catch {
                    throw DatabaseError.corruptedData(
                        namespace: namespace,
                        details:   "Décodage \(type) échoué : \(error)"
                    )
                }
            }
        }
    }

    func performFetchOne<T: Storable>(
        _ type: T.Type,
        id: T.ID,
        namespace: String
    ) async throws -> T? {
        let ctx = try readContext(for: namespace)
        let req = NSFetchRequest<NSManagedObject>(entityName: Keys.entityName)
        req.predicate = NSPredicate(
            format: "%K == %@ AND %K == %@",
            Keys.entityType, "\(type)",
            Keys.entityId,   "\(id)"
        )
        req.fetchLimit = 1
        return try await ctx.perform {
            guard
                let obj  = try ctx.fetch(req).first,
                let data = obj.value(forKey: Keys.jsonPayload) as? Data
            else { return nil }
            return try? self.decoder.decode(type, from: data)
        }
    }

    func performCount<T: Storable>(
        _ type: T.Type,
        namespace: String,
        query: QuerySpec?
    ) async throws -> Int {
        let ctx = try readContext(for: namespace)
        let req = Self.fetchRequest(entityType: "\(type)", query: query)
        return try await ctx.perform { try ctx.count(for: req) }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: CRUD — Delete
    // ─────────────────────────────────────────────────────────

    func performDelete<T: Storable>(
        _ type: T.Type,
        id: T.ID,
        namespace: String
    ) async throws {
        let ctx = try writeContext(for: namespace)
        let req = NSFetchRequest<NSManagedObject>(entityName: Keys.entityName)
        req.predicate = NSPredicate(
            format: "%K == %@ AND %K == %@",
            Keys.entityType, "\(type)",
            Keys.entityId,   "\(id)"
        )
        req.fetchLimit = 1
        try await ctx.perform {
            guard let obj = try ctx.fetch(req).first else {
                throw DatabaseError.notFound(
                    id: "\(id)", type: "\(type)", namespace: namespace
                )
            }
            ctx.delete(obj)
            try self.saveIfNotInTransaction(ctx: ctx, namespace: namespace)
        }
    }

    func performDeleteAll<T: Storable>(
        _ type: T.Type,
        namespace: String,
        query: QuerySpec?
    ) async throws {
        let ctx = try writeContext(for: namespace)
        let req = Self.fetchRequest(entityType: "\(type)", query: query)
        try await ctx.perform {
            try ctx.fetch(req).forEach { ctx.delete($0) }
            try self.saveIfNotInTransaction(ctx: ctx, namespace: namespace)
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Transactions
    // ─────────────────────────────────────────────────────────

    func beginTransaction(namespace: String) async throws {
        guard !inTransaction.contains(namespace) else {
            throw DatabaseError.transactionAlreadyActive(namespace: namespace)
        }
        // Les saves suivants ne feront pas ctx.save() — ils accumulent
        inTransaction.insert(namespace)
    }

    func commitTransaction(namespace: String) async throws {
        guard inTransaction.contains(namespace) else { return }
        let ctx = try writeContext(for: namespace)
        try await ctx.perform {
            if ctx.hasChanges { try ctx.save() }
        }
        inTransaction.remove(namespace)
    }

    func rollbackTransaction(namespace: String) async throws {
        guard inTransaction.contains(namespace) else { return }
        let ctx = try writeContext(for: namespace)
        await ctx.perform { ctx.rollback() }
        inTransaction.remove(namespace)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Observation
    // ─────────────────────────────────────────────────────────

    func performObserve<T: Storable>(
        _ type: T.Type,
        namespace: String,
        query: QuerySpec?
    ) -> AsyncStream<Result<[T], DatabaseError>> {
        AsyncStream { continuation in
            Task {
                // Émission initiale
                do {
                    let initial = try await self.performFetch(
                        type, namespace: namespace, query: query
                    )
                    continuation.yield(.success(initial))
                } catch {
                    continuation.yield(
                        .failure(.readFailed(namespace: namespace, underlying: error))
                    )
                }

                // Souscription à NSManagedObjectContextDidSave
                // Émis à chaque ctx.save() dans ce processus
                let observer = NotificationCenter.default.addObserver(
                    forName: .NSManagedObjectContextDidSave,
                    object:  nil,
                    queue:   nil
                ) { _ in
                    Task {
                        do {
                            let results = try await self.performFetch(
                                type, namespace: namespace, query: query
                            )
                            continuation.yield(.success(results))
                        } catch {
                            continuation.yield(
                                .failure(.readFailed(namespace: namespace, underlying: error))
                            )
                        }
                    }
                }

                continuation.onTermination = { _ in
                    NotificationCenter.default.removeObserver(observer)
                }
            }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Maintenance
    // ─────────────────────────────────────────────────────────

    func performClearAll(namespace: String) async throws {
        let ctx = try writeContext(for: namespace)
        let req = NSFetchRequest<NSManagedObject>(entityName: Keys.entityName)
        try await ctx.perform {
            try ctx.fetch(req).forEach { ctx.delete($0) }
            if ctx.hasChanges { try ctx.save() }
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Helpers privés
    // ─────────────────────────────────────────────────────────

    /// Insert ou met à jour le proxy pour un entityId donné.
    private func upsertProxy(
        id:        String,
        type:      String,
        namespace: String,
        in ctx:    NSManagedObjectContext
    ) throws -> NSManagedObject {
        let req = NSFetchRequest<NSManagedObject>(entityName: Keys.entityName)
        req.predicate  = NSPredicate(format: "%K == %@", Keys.entityId, id)
        req.fetchLimit = 1

        if let existing = try ctx.fetch(req).first { return existing }

        let proxy = NSEntityDescription.insertNewObject(
            forEntityName: Keys.entityName, into: ctx
        )
        proxy.setValue(id,        forKey: Keys.entityId)
        proxy.setValue(type,      forKey: Keys.entityType)
        proxy.setValue(namespace, forKey: Keys.namespace)
        proxy.setValue(Date(),    forKey: Keys.createdAt)
        proxy.setValue(Date(),    forKey: Keys.updatedAt)
        return proxy
    }

    /// Sauvegarde le context seulement si on n'est pas dans une transaction.
    private func saveIfNotInTransaction(
        ctx:       NSManagedObjectContext,
        namespace: String
    ) throws {
        guard !inTransaction.contains(namespace), ctx.hasChanges else { return }
        try ctx.save()
    }

    /// NSFetchRequest depuis un QuerySpec.
    private static func fetchRequest(
        entityType: String,
        query:      QuerySpec?
    ) -> NSFetchRequest<NSManagedObject> {
        let req = NSFetchRequest<NSManagedObject>(entityName: Keys.entityName)
        req.predicate = NSPredicate(format: "%K == %@", Keys.entityType, entityType)
        if let limit  = query?.limit  { req.fetchLimit  = limit  }
        if let offset = query?.offset { req.fetchOffset = offset }
        if let sorts  = query?.sort, !sorts.isEmpty {
            req.sortDescriptors = sorts.map {
                NSSortDescriptor(key: $0.keyPath, ascending: $0.ascending)
            }
        }
        return req
    }

    // ─────────────────────────────────────────────────────────
    // MARK: NSManagedObjectModel en mémoire
    // ─────────────────────────────────────────────────────────
    //
    // Avantages vs .xcdatamodeld :
    //   - pas de fichier de ressource à maintenir
    //   - schéma visible directement dans le code
    //   - swap d'engine facilité (rien à supprimer dans le bundle)
    //
    // L'entité EntityProxy est le proxy générique qui stocke
    // toutes les entités Storable sérialisées en JSON.
    // Chaque feature garde ses structs Swift propres —
    // CoreData ne voit qu'un gros blob Data par entité.

    static func buildModel() -> NSManagedObjectModel {
        let model  = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name                   = Keys.entityName
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)

        func attr(
            _ name:    String,
            _ type:    NSAttributeType,
            indexed:   Bool = false,
            optional:  Bool = false
        ) -> NSAttributeDescription {
            let a           = NSAttributeDescription()
            a.name          = name
            a.attributeType = type
            a.isOptional    = optional
            a.isIndexed     = indexed
            return a
        }

        entity.properties = [
            attr(Keys.entityId,    .stringAttributeType,  indexed:  true),
            attr(Keys.entityType,  .stringAttributeType,  indexed:  true),
            attr(Keys.namespace,   .stringAttributeType,  indexed:  true),
            attr(Keys.jsonPayload, .binaryDataAttributeType),
            attr(Keys.createdAt,   .dateAttributeType),
            attr(Keys.updatedAt,   .dateAttributeType,    indexed:  true),
        ]

        // Index composite entityType + updatedAt DESC
        // → fetch par type trié par date très rapide
        let idxType = NSFetchIndexElementDescription(
            property:      entity.propertiesByName[Keys.entityType]!,
            collationType: .binary
        )
        idxType.isAscending = true

        let idxDate = NSFetchIndexElementDescription(
            property:      entity.propertiesByName[Keys.updatedAt]!,
            collationType: .binary
        )
        idxDate.isAscending = false

        let compositeIndex = NSFetchIndexDescription(
            name:     "idx_type_updated",
            elements: [idxType, idxDate]
        )
        entity.indexes = [compositeIndex]
        model.entities = [entity]
        return model
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Keys
    // ─────────────────────────────────────────────────────────

    private enum Keys {
        static let entityName  = "EntityProxy"
        static let entityId    = "entityId"
        static let entityType  = "entityType"
        static let namespace   = "namespace"
        static let jsonPayload = "jsonPayload"
        static let createdAt   = "createdAt"
        static let updatedAt   = "updatedAt"
    }
}
