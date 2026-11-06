//
//  SQLiteSchemaBuilder.swift
//  AppModules
//
//  Created by Asyst on 5/18/26.
//


// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/Engines/SQLiteSchemaBuilder.swift        │
// │                                                              │
// │  INTERNE — construit le schéma SQL pour chaque entité        │
// │  SQLiteStorable enregistrée dans SQLiteEngine.               │
// │                                                              │
// │  Stratégie de stockage :                                     │
// │    - Entités SQLiteStorable → table dédiée avec colonnes     │
// │      réelles (id, champs indexés, clés étrangères, payload)  │
// │    - Entités Storable simples → table proxy JSON générique   │
// │      (même approche que CoreDataEngine)                      │
// │    - Table FTS5 synchronisée automatiquement pour chaque     │
// │      entité qui déclare fulltextFields                       │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import GRDB
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: SQLiteSchemaBuilder
// ─────────────────────────────────────────────────────────────

struct SQLiteSchemaBuilder {

    // ── Registre des entités SQLiteStorable par namespace ─────
    // Rempli au démarrage via SQLiteEngine.register()
    private(set) var registrations: [String: [SQLiteEntityRegistration]] = [:]

    // Colonnes gérées automatiquement — ignorées si déclarées dans indexedFields ou foreignKeys
    static let reservedColumns: Set<String> = [
        "id", "json_payload", "created_at", "updated_at",
        // Variantes camelCase — normalisées automatiquement
        "createdAt", "updatedAt", "jsonPayload"
    ]

    mutating func register<T: Storable>(_ type: T.Type, namespace: String) {
        // Normalise camelCase → snake_case ET filtre les réservés
        let filteredIndexed = type.indexedFields
            .map { Self.camelToSnake($0) }
            .filter { !Self.reservedColumns.contains($0) }

        // FTS5 ne peut indexer que des colonnes SQL réelles.
        // Un champ fulltextFields doit aussi être dans indexedFields
        // pour exister comme colonne dans la table principale.
        // On filtre silencieusement les champs non couverts.
        let indexedSet = Set(filteredIndexed)
        let filteredFTS = type.searchableFields
            .map { Self.camelToSnake($0) }
            .filter { indexedSet.contains($0) }

        if filteredFTS.count != type.searchableFields.count {
            let missing = type.searchableFields
                .map { Self.camelToSnake($0) }
                .filter { !indexedSet.contains($0) }
            debugLog("⚠️ [\(type)] fulltextFields ignorés car absents de indexedFields : \(missing)")
            debugLog("   → Ajouter ces champs dans indexedFields pour activer FTS5 dessus.")
        }

        let filteredFKs = type.foreignKeys
            .filter { !Self.reservedColumns.contains($0.column) && !Self.reservedColumns.contains(Self.camelToSnake($0.column)) }
            .map { fk in
                StorableForeignKey(
                    Self.camelToSnake(fk.column),
                    references: fk.referencesTable,
                    onDelete: fk.onDelete
                )
            }

        let reg = SQLiteEntityRegistration(
            entityType:     "\(type)",
            tableName:      Self.tableName(for: type),
            ftsTtableName:  Self.ftsTableName(for: type),
            fulltextFields: filteredFTS,
            indexedFields:  filteredIndexed,
            foreignKeys:    filteredFKs
        )
        registrations[namespace, default: []].append(reg)
    }

    // Conversion camelCase → snake_case
    static func camelToSnake(_ input: String) -> String {
        var result = ""
        for char in input {
            if char.isUppercase {
                if !result.isEmpty { result += "_" }
                result += char.lowercased()
            } else {
                result += String(char)
            }
        }
        return result
    }

    /// Ordonne les tables pour que chaque table référencée existe avant les FOREIGN KEY.
    func sortedRegistrationsForCreation(_ regs: [SQLiteEntityRegistration]) -> [SQLiteEntityRegistration] {
        guard regs.count > 1 else { return regs }

        let tableToReg = Dictionary(uniqueKeysWithValues: regs.map { ($0.tableName, $0) })
        let knownTables = Set(tableToReg.keys)

        var inDegree: [String: Int] = [:]
        var dependents: [String: [String]] = [:]

        for reg in regs {
            let externalDeps = Set(
                reg.foreignKeys
                    .map(\.referencesTable)
                    .filter { $0 != reg.tableName && knownTables.contains($0) }
            )
            inDegree[reg.tableName] = externalDeps.count
            for dep in externalDeps {
                dependents[dep, default: []].append(reg.tableName)
            }
        }

        var queue = regs
            .filter { (inDegree[$0.tableName] ?? 0) == 0 }
            .map(\.tableName)
        var sorted: [SQLiteEntityRegistration] = []
        var visited = Set<String>()

        while let tableName = queue.first {
            queue.removeFirst()
            guard !visited.contains(tableName), let reg = tableToReg[tableName] else { continue }
            visited.insert(tableName)
            sorted.append(reg)

            for dependent in dependents[tableName] ?? [] {
                let remaining = (inDegree[dependent] ?? 1) - 1
                inDegree[dependent] = remaining
                if remaining == 0 {
                    queue.append(dependent)
                }
            }
        }

        // Cycles ou dépendances externes — conserver l'ordre d'enregistrement pour le reste
        for reg in regs where !visited.contains(reg.tableName) {
            sorted.append(reg)
        }

        return sorted
    }

    // ── Création du schéma complet pour un namespace ──────────

    func createSchema(in db: Database, namespace: String) throws {

        // 1. Table proxy JSON générique (fallback pour Storable simple)
        try createProxyTable(in: db)

        // 2. Tables dédiées — ordre topologique pour respecter les FOREIGN KEY
        let regs = sortedRegistrationsForCreation(registrations[namespace] ?? [])
        for reg in regs {
            try createEntityTable(in: db, registration: reg)
            if !reg.fulltextFields.isEmpty {
                try createFTSTable(in: db, registration: reg)
            }
        }

        // 3. Table RelationIndex pour les jointures efficaces
        try createRelationIndexTable(in: db)
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Table proxy JSON (entités Storable simples)
    // ─────────────────────────────────────────────────────────

    private func createProxyTable(in db: Database) throws {
        try db.create(table: "entity_proxy", ifNotExists: true) { t in
            t.column("entity_id",    .text).primaryKey()
            t.column("entity_type",  .text).notNull().indexed()
            t.column("namespace",    .text).notNull().indexed()
            t.column("json_payload", .blob).notNull()
            t.column("created_at",   .datetime).notNull()
            t.column("updated_at",   .datetime).notNull().indexed()
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Table dédiée (entités SQLiteStorable)
    // ─────────────────────────────────────────────────────────
    // Chaque entité SQLiteStorable a sa propre table avec :
    //   - id              : clé primaire
    //   - champs indexés  : colonnes SQL réelles pour les jointures et filtres
    //   - json_payload    : le reste de l'entité en JSON
    //   - timestamps      : created_at, updated_at
    //   - clés étrangères : avec CASCADE optionnel

    private func createEntityTable(in db: Database, registration: SQLiteEntityRegistration) throws {
        let foreignKeysByColumn = Dictionary(
            uniqueKeysWithValues: registration.foreignKeys.map { ($0.column, $0) }
        )

        try db.create(table: registration.tableName, ifNotExists: true) { t in

            t.column("id", .text).primaryKey()

            // indexedFields — colonnes pour filtres et jointures (+ FK si déclarée sur le même champ)
            for field in registration.indexedFields {
                if let fk = foreignKeysByColumn[field] {
                    t.column(field, .text)
                        .indexed()
                        .references(fk.referencesTable, onDelete: fk.onDelete.grdbAction)
                } else {
                    t.column(field, .text).indexed()
                }
            }

            // fulltextFields — colonnes pour FTS5 (dédupliquées avec indexedFields)
            // Nécessaire car FTS5 synchronize() requiert des colonnes réelles
            let alreadyAdded = Set(registration.indexedFields)
            for field in registration.fulltextFields where !alreadyAdded.contains(field) {
                t.column(field, .text)
            }

            // foreignKeys sur colonnes non déjà créées via indexedFields
            let allAdded = alreadyAdded.union(Set(registration.fulltextFields))
            for fk in registration.foreignKeys where !allAdded.contains(fk.column) {
                t.column(fk.column, .text)
                    .references(fk.referencesTable, onDelete: fk.onDelete.grdbAction)
                    .indexed()
            }

            // Colonnes par défaut — toujours présentes
            t.column("json_payload", .blob).notNull()
            t.column("created_at",   .datetime).notNull()
            t.column("updated_at",   .datetime).notNull().indexed()
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Table FTS5
    // ─────────────────────────────────────────────────────────
    // Synchronisée automatiquement avec la table principale.
    // FTS5 maintient un index inversé — recherche en < 2ms sur 1M lignes.

    private func createFTSTable(in db: Database, registration: SQLiteEntityRegistration) throws {
        try db.create(
            virtualTable: registration.ftsTtableName,
            ifNotExists:  true,
            using:        FTS5()
        ) { t in
            // Synchronisation automatique avec la table principale
            t.synchronize(withTable: registration.tableName)
            // Colonnes indexées pour la recherche
            for field in registration.fulltextFields {
                t.column(field)
            }
            // Tokenizer unicode61 : gère accents, majuscules, multilingue
            t.tokenizer = .unicode61()
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Table RelationIndex
    // ─────────────────────────────────────────────────────────
    // Stocke les relations explicitement pour les jointures
    // entre namespaces différents.

    private func createRelationIndexTable(in db: Database) throws {
        try db.create(table: "relation_index", ifNotExists: true) { t in
            t.column("child_id",    .text).notNull().indexed()
            t.column("child_type",  .text).notNull().indexed()
            t.column("parent_id",   .text).notNull().indexed()
            t.column("parent_type", .text).notNull().indexed()
            t.uniqueKey(["child_id", "child_type", "parent_id", "parent_type"])
        }
    }

    // ─────────────────────────────────────────────────────────
    // MARK: Helpers
    // ─────────────────────────────────────────────────────────

    static func tableName<T: Storable>(for type: T.Type) -> String {
        "\(T.namespace)_\(String(describing: type).lowercased())s"
    }

    static func ftsTableName<T: Storable>(for type: T.Type) -> String {
        "\(tableName(for: type))_fts"
    }
}

// ─────────────────────────────────────────────────────────────
// MARK: SQLiteEntityRegistration
// ─────────────────────────────────────────────────────────────

struct SQLiteEntityRegistration {
    let entityType:     String
    let tableName:      String
    let ftsTtableName:  String
    let fulltextFields: [String]
    let indexedFields:  [String]
    let foreignKeys:    [StorableForeignKey]

    var hasFTS: Bool { !fulltextFields.isEmpty }
}

// ─────────────────────────────────────────────────────────────
// MARK: ForeignKeyAction → GRDB
// ─────────────────────────────────────────────────────────────

extension ForeignKeyAction {
    var grdbAction: Database.ForeignKeyAction {
        switch self {
        case .cascade:  return .cascade
        case .setNull:  return .setNull
        case .restrict: return .restrict
        case .noAction: return .setDefault  // GRDB n'a pas .noAction → .setDefault est l'équivalent
        }
    }
}
