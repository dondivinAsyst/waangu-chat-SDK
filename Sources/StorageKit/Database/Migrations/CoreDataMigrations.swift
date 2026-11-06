//
//  CoreDataMigrations.swift
//  AppModules
//
//  Created by Asyst on 5/17/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/Migrations/CoreDataMigrations.swift      │
// │                                                              │
// │  INTERNE — contexte et étapes de migration propres à         │
// │  CoreDataEngine.                                             │
// │                                                              │
// │  Hiérarchie :                                                │
// │    MigrationStep (CoreKit)                                   │
// │      └─ EngineCapableMigrationStep (StorageKit/Contracts)    │
// │            └─ CoreDataMigrationStep (ce fichier)             │
// │                  reçoit CoreDataMigrationContext (ce fichier)│
// │                                                              │
// │  MigrationManager ne voit que EngineCapableMigrationStep     │
// │  et EngineMigrationContext — jamais les types concrets ici.  │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import CoreData
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: CoreDataMigrationContext
// ─────────────────────────────────────────────────────────────

/// Contexte opaque fourni par CoreDataEngine à MigrationManager.
/// MigrationManager le passe aux étapes sans jamais l'inspecter.
/// Les étapes CoreData le castent pour accéder à l'API CoreData.
final class CoreDataMigrationContext: EngineMigrationContext, @unchecked Sendable {

    let namespace: String
    let storeURL:  URL

    init(namespace: String, storeURL: URL) {
        self.namespace = namespace
        self.storeURL  = storeURL
    }

    // ── Helpers exposés aux étapes ────────────────────────────

    /// Modèle cible : version actuelle du code.
    func currentModel() -> NSManagedObjectModel {
        CoreDataEngine.buildModel()
    }

    /// Modèle source : version stockée dans le fichier sqlite existant.
    /// `nil` si le store n'existe pas encore (première installation).
    func sourceModel() -> NSManagedObjectModel? {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return nil }
        guard let meta = try? NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: storeURL, options: nil
        ) else { return nil }
        return NSManagedObjectModel.mergedModel(from: nil, forStoreMetadata: meta)
    }

    /// Migration progressive via NSMigrationManager.
    /// Écrit dans un fichier temporaire puis remplace le store.
    func migrateStore(
        source:      NSManagedObjectModel,
        destination: NSManagedObjectModel,
        mapping:     NSMappingModel
    ) throws {
        let tempURL = storeURL
            .deletingLastPathComponent()
            .appending(path: "\(namespace)_migrating.sqlite")

        let manager = NSMigrationManager(
            sourceModel:      source,
            destinationModel: destination
        )
        try manager.migrateStore(
            from:               storeURL,
            sourceType:         NSSQLiteStoreType,
            options:            nil,
            with:               mapping,
            toDestinationURL:   tempURL,
            destinationType:    NSSQLiteStoreType,
            destinationOptions: nil
        )

        if FileManager.default.fileExists(atPath: storeURL.path) {
            try FileManager.default.removeItem(at: storeURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: storeURL)
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: CoreDataMigrationStep
// ─────────────────────────────────────────────────────────────

/// Raffinement de EngineCapableMigrationStep avec un contexte CoreData typé.
/// Evite le cast manuel dans chaque étape concrète.
protocol CoreDataMigrationStep: EngineCapableMigrationStep {
    func validate(in context: CoreDataMigrationContext) async throws
    func perform(in context: CoreDataMigrationContext) async throws
    func rollback(in context: CoreDataMigrationContext) async throws
}

extension CoreDataMigrationStep {

    func validate(in context: any EngineMigrationContext) async throws {
        guard let ctx = context as? CoreDataMigrationContext else { return }
        try await validate(in: ctx)
    }

    func perform(in context: any EngineMigrationContext) async throws {
        guard let ctx = context as? CoreDataMigrationContext else { return }
        try await perform(in: ctx)
    }

    func rollback(in context: any EngineMigrationContext) async throws {
        guard let ctx = context as? CoreDataMigrationContext else { return }
        try await rollback(in: ctx)
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: CoreDataLightweightMigration
// ─────────────────────────────────────────────────────────────
// Cas couverts :
//   - ajout d'un attribut optionnel
//   - renommage via renamingIdentifier dans buildModel()
//   - suppression d'un attribut
//
// CoreData le fait automatiquement (shouldMigrateStoreAutomatically = true).
// Cette étape documente le passage de version et valide que c'est possible.

public struct CoreDataLightweightMigration: CoreDataMigrationStep {
    public let fromVersion: Int
    public let toVersion:   Int
    public var description: String { "Migration légère v\(fromVersion)→v\(toVersion)" }

    public init(from fromVersion: Int, to toVersion: Int) {
        self.fromVersion = fromVersion
        self.toVersion   = toVersion
    }

    func validate(in context: CoreDataMigrationContext) async throws {
        guard let source = context.sourceModel() else { return }
        guard (try? NSMappingModel.inferredMappingModel(
            forSourceModel:   source,
            destinationModel: context.currentModel()
        )) != nil else {
            throw DatabaseError.migrationDryRunFailed(
                namespace:   context.namespace,
                fromVersion: fromVersion,
                toVersion:   toVersion,
                reason:      "Mapping inféré impossible — utiliser CoreDataHeavyweightMigration"
            )
        }
    }

    func perform(in context: CoreDataMigrationContext) async throws {
        // CoreData gère la migration au prochain loadPersistentStores().
        // Cette méthode met à jour le .meta.json via MigrationManager.
    }

    func rollback(in context: CoreDataMigrationContext) async throws {
        // Le backup fichier de MigrationManager suffit.
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: CoreDataHeavyweightMigration
// ─────────────────────────────────────────────────────────────
// Cas couverts :
//   - changement de type d'un attribut
//   - restructuration de relations
//   - transformation de données via NSEntityMigrationPolicy

public struct CoreDataHeavyweightMigration: CoreDataMigrationStep {
    public let fromVersion:  Int
    public let toVersion:    Int
    public let mappingModel: NSMappingModel
    public var description: String { "Migration lourde v\(fromVersion)→v\(toVersion)" }

    public init(from fromVersion: Int, to toVersion: Int, mappingModel: NSMappingModel) {
        self.fromVersion  = fromVersion
        self.toVersion    = toVersion
        self.mappingModel = mappingModel
    }

    func validate(in context: CoreDataMigrationContext) async throws {
        guard FileManager.default.fileExists(atPath: context.storeURL.path) else { return }
        guard context.sourceModel() != nil else {
            throw DatabaseError.migrationDryRunFailed(
                namespace:   context.namespace,
                fromVersion: fromVersion,
                toVersion:   toVersion,
                reason:      "Modèle source introuvable dans les métadonnées du store"
            )
        }
    }

    func perform(in context: CoreDataMigrationContext) async throws {
        guard let source = context.sourceModel() else { return }
        try context.migrateStore(
            source:      source,
            destination: context.currentModel(),
            mapping:     mappingModel
        )
    }

    func rollback(in context: CoreDataMigrationContext) async throws {
        // Le backup fichier de MigrationManager suffit.
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: Note sur les index
// ─────────────────────────────────────────────────────────────
// Les index se déclarent dans CoreDataEngine.buildModel() via
// NSFetchIndexDescription + NSFetchIndexElementDescription.
// CoreData les crée et les maintient automatiquement.
//
// Il n'existe pas d'étape de migration dédiée aux index :
// si tu ajoutes un index dans buildModel(), CoreData le crée
// lors du prochain loadPersistentStores() avec la migration légère.
//
// Ne jamais appeler sqlite3_* directement sur un store CoreData —
// SQLite est un détail d'implémentation interne d'Apple.
