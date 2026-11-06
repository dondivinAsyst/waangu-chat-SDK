//
//  MigrationManager.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                        │
// │  FICHIER : Database/Migrations/MigrationManager.swift        │
// │                                                              │
// │  INTERNE — appelé par chaque engine dans son setup().        │
// │                                                              │
// │  Responsabilités (et UNIQUEMENT celles-ci) :                 │
// │    1. Lire / écrire la version courante (.meta.json)         │
// │    2. Filtrer et ordonner les étapes manquantes              │
// │    3. Dry-run avant chaque étape                             │
// │    4. Backup du fichier store avant exécution                │
// │    5. Appeler perform() si dry-run OK                        │
// │    6. Rollback + restauration backup si perform() échoue     │
// │    7. Pruning des vieux backups                              │
// │                                                              │
// │  Ce qu'il ne fait PAS :                                      │
// │    - Ouvrir une connexion base de données                    │
// │    - Écrire du SQL, du NSManagedObjectModel, du Realm…       │
// │    - Choisir comment migrer (c'est le rôle de l'étape)       │
// │    - Connaître SwiftDataMigrationContext ou tout autre ctx   │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: MigrationManager
// ─────────────────────────────────────────────────────────────

actor MigrationManager {

    // ─────────────────────────────────────────────────────────
    // MARK: Entry point
    // ─────────────────────────────────────────────────────────

    /// Appelé par l'engine après avoir construit son contexte concret.
    ///
    /// - Parameters:
    ///   - steps:    toutes les étapes connues (filtrées ici par version)
    ///   - namespace: namespace concerné
    ///   - storeURL: URL du fichier store (pour backup — peut être un
    ///               répertoire pour CoreData ou Realm)
    ///   - context:  contexte opaque fourni par l'engine ;
    ///               MigrationManager le transmet sans jamais l'inspecter
    func run(
        steps: [any MigrationStep],
        namespace: String,
        storeURL: URL,
        context: any EngineMigrationContext
    ) async throws {
        let currentVersion = try readCurrentVersion(namespace: namespace, storeURL: storeURL)

        // Ne conserve que les étapes qui parlent la langue de cet engine
        // ET dont la version source est >= la version actuelle.
        let pending = steps
            .compactMap { $0 as? any EngineCapableMigrationStep }
            .filter { $0.fromVersion >= currentVersion }
            .sorted { $0.fromVersion < $1.fromVersion }

        guard !pending.isEmpty else { return }

        for step in pending {
            try await execute(step, namespace: namespace, storeURL: storeURL, context: context)
        }

        try pruneBackups(namespace: namespace, storeURL: storeURL, keepLast: 3)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Étape individuelle
    // ─────────────────────────────────────────────────────────

    private func execute(
        _ step: any EngineCapableMigrationStep,
        namespace: String,
        storeURL: URL,
        context: any EngineMigrationContext
    ) async throws {

        // 1. Dry-run — valide sans modifier
        do {
            try await step.validate(in: context)
        } catch {
            throw DatabaseError.migrationDryRunFailed(
                namespace: namespace,
                fromVersion: step.fromVersion,
                toVersion: step.toVersion,
                reason: error.localizedDescription
            )
        }

        // 2. Backup du fichier store avant toute modification
        let backupURL = try createBackup(
            of: storeURL,
            namespace: namespace,
            version: step.fromVersion
        )

        // 3. Migration réelle
        do {
            try await step.perform(in: context)
            try writeCurrentVersion(
                step.toVersion,
                namespace: namespace,
                storeURL: storeURL
            )
            // Backup supprimé si migration réussie
            try? FileManager.default.removeItem(at: backupURL)

        } catch {
            // Rollback applicatif (best-effort)
            try? await step.rollback(in: context)
            // Restauration du backup si l'état est incohérent
            try restoreBackup(from: backupURL, to: storeURL)
            throw DatabaseError.migrationFailed(
                namespace: namespace,
                fromVersion: step.fromVersion,
                toVersion: step.toVersion,
                underlying: error
            )
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Versioning (.meta.json)
    // ─────────────────────────────────────────────────────────
    // Stocké à côté du fichier store, indépendamment de l'engine.
    // Un engine qui ne stocke pas de version en interne (ex. InMemory)
    // bénéficie quand même du versioning via ce fichier.

    private func metaURL(namespace: String, storeURL: URL) -> URL {
        storeURL.deletingLastPathComponent()
            .appending(path: "\(namespace).meta.json")
    }

    private func readCurrentVersion(namespace: String, storeURL: URL) throws -> Int {
        let url = metaURL(namespace: namespace, storeURL: storeURL)
        guard
            let data = try? Data(contentsOf: url),
            let meta = try? JSONDecoder().decode(StoreMeta.self, from: data)
        else { return 0 }
        return meta.schemaVersion
    }

    private func writeCurrentVersion(
        _ version: Int,
        namespace: String,
        storeURL: URL
    ) throws {
        let meta = StoreMeta(
            namespace: namespace,
            schemaVersion: version,
            lastMigrationDate: Date()
        )
        let data = try JSONEncoder().encode(meta)
        try data.write(to: metaURL(namespace: namespace, storeURL: storeURL), options: .atomic)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Backup & Restore
    // ─────────────────────────────────────────────────────────
    // Copie de fichier agnostique — fonctionne pour SQLite,
    // CoreData (bundle .sqlite + WAL + SHM), Realm (.realm + .lock…),
    // ou tout autre format fichier.

    @discardableResult
    private func createBackup(
        of storeURL: URL,
        namespace: String,
        version: Int
    ) throws -> URL {
        let ts = ISO8601DateFormatter()
            .string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let backupDir = storeURL
            .deletingLastPathComponent()
            .appending(path: "backups")
        try FileManager.default.createDirectory(
            at: backupDir,
            withIntermediateDirectories: true
        )

        let ext      = storeURL.pathExtension
        let filename = ext.isEmpty
            ? "\(namespace)_v\(version)_\(ts)"
            : "\(namespace)_v\(version)_\(ts).\(ext)"
        let backupURL = backupDir.appending(path: filename)

        try FileManager.default.copyItem(at: storeURL, to: backupURL)

        // Copie des fichiers satellites (WAL/SHM pour SQLite et SwiftData,
        // .lock/.note/.management pour Realm…)
        for satellite in ["wal", "shm", "lock", "note", "management"] {
            let src = storeURL.appendingPathExtension(satellite)
            if FileManager.default.fileExists(atPath: src.path) {
                try? FileManager.default.copyItem(
                    at: src,
                    to: backupURL.appendingPathExtension(satellite)
                )
            }
        }
        return backupURL
    }

    private func restoreBackup(from backupURL: URL, to storeURL: URL) throws {
        if FileManager.default.fileExists(atPath: storeURL.path) {
            try FileManager.default.removeItem(at: storeURL)
        }
        try FileManager.default.copyItem(at: backupURL, to: storeURL)
    }

    private func pruneBackups(namespace: String, storeURL: URL, keepLast: Int) throws {
        let backupDir = storeURL
            .deletingLastPathComponent()
            .appending(path: "backups")
        guard FileManager.default.fileExists(atPath: backupDir.path) else { return }

        let all = try FileManager.default.contentsOfDirectory(
            at: backupDir,
            includingPropertiesForKeys: [.creationDateKey]
        )
        let sorted = all
            .filter { $0.lastPathComponent.hasPrefix(namespace) }
            .sorted {
                let d1 = (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let d2 = (try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return d1 > d2  // plus récent en premier
            }
        for url in sorted.dropFirst(keepLast) {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: StoreMeta — fichier de versioning
// ─────────────────────────────────────────────────────────────

private struct StoreMeta: Codable {
    let namespace: String
    let schemaVersion: Int
    let lastMigrationDate: Date
}
