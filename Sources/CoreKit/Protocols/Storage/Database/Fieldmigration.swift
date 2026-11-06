//
//  Fieldmigration.swift
//  AppModules
//
//  Created by Asyst on 6/15/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : CoreKit                                            │
// │  FICHIER : Database/FieldMigration.swift                     │
// │                                                              │
// │  Migration agnostique pour ajouter un champ à une entité.   │
// │  Couvre 90% des cas de migration.                            │
// │                                                              │
// │  La feature décrit le changement en termes Swift.            │
// │  Chaque engine traduit à sa façon :                          │
// │    SQLiteEngine   → ALTER TABLE ADD COLUMN                   │
// │    CoreDataEngine → ignoré (migration légère automatique)    │
// │    RealmEngine    → migrationBlock                           │
// │    InMemoryEngine → ignoré                                   │
// │                                                              │
// │  Pour les cas complexes (transformation de données,          │
// │  split de table), utiliser les migrations spécifiques        │
// │  à l'engine (SQLiteRawMigration, etc.) — compromis assumé.  │
// └──────────────────────────────────────────────────────────────┘

import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: FieldMigration
// ─────────────────────────────────────────────────────────────

public struct FieldMigration: MigrationStep, Sendable {

    public let fromVersion:  Int
    public let toVersion:    Int

    /// Nom du type Swift — pas un nom de table SQL.
    /// Ex: "ContactModel", "Trip", "Message"
    public let entityName:   String

    /// Nom du champ Swift — pas un nom de colonne SQL.
    /// Ex: "isTitle", "sendMessagesHistory"
    /// StorageKit normalise camelCase → snake_case automatiquement.
    public let fieldName:    String

    /// Valeur par défaut pour les enregistrements existants.
    /// StorageKit infère le type SQL depuis cette valeur :
    ///   "0" ou "1"    → INTEGER
    ///   "0.0"         → REAL
    ///   nil           → TEXT (nullable)
    ///   "'some text'" → TEXT avec valeur par défaut
    public let defaultValue: String?

    public var description: String {
        "Ajout de \(fieldName) sur \(entityName) v\(fromVersion)→v\(toVersion)"
    }

    // ── Init avec type Storable ──────────────────────────────

    public init(
        from:         Int,
        to:           Int,
        entity:       any Storable.Type,
        field:        String,
        defaultValue: String? = nil
    ) {
        self.fromVersion  = from
        self.toVersion    = to
        self.entityName   = "\(entity)"
        self.fieldName    = field
        self.defaultValue = defaultValue
    }

    // ── Init avec nom string (pour entités pas encore importées) ─

    public init(
        from:         Int,
        to:           Int,
        entityName:   String,
        field:        String,
        defaultValue: String? = nil
    ) {
        self.fromVersion  = from
        self.toVersion    = to
        self.entityName   = entityName
        self.fieldName    = field
        self.defaultValue = defaultValue
    }
}
