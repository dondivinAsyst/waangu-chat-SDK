//
//  Fieldmigrationtranslator.swift
//  AppModules
//
//  Created by Asyst on 6/15/26.
//

//
//  Fieldmigrationtranslator.swift
//  AppModules
//
//  Created by Asyst on 6/15/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/Migrations/FieldMigrationTranslator.swift│
// │                                                              │
// │  INTERNE — traduit FieldMigration (CoreKit, agnostique)      │
// │  en SQLiteAddColumnMigration (StorageKit, SQL concret).      │
// │                                                              │
// │  Appelé par SQLiteEngine.setup() lors de l'enregistrement    │
// │  des migrations dans GRDB DatabaseMigrator.                  │
// │                                                              │
// │  CoreDataEngine ignore les FieldMigration car CoreData       │
// │  gère les ajouts de champs automatiquement.                  │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: FieldMigrationTranslator
// ─────────────────────────────────────────────────────────────

enum FieldMigrationTranslator {

    /// Traduit une FieldMigration agnostique en SQLiteAddColumnMigration.
    ///
    /// - Parameters:
    ///   - field:     la migration agnostique (CoreKit)
    ///   - namespace: le namespace de l'entité (ex: "chat", "ride")
    ///   - registrations: les entités enregistrées dans ce namespace
    /// - Returns: une SQLiteAddColumnMigration prête à exécuter
    static func translate(
        _ field:        FieldMigration,
        namespace:      String,
        registrations:  [SQLiteEntityRegistration]
    ) -> SQLiteAddColumnMigration {

        // 1. Nom de table : cherche dans les registrations par entityType
        //    Ex: "ContactModel" → "chat_contactmodels"
        let tableName: String
        if let reg = registrations.first(where: { $0.entityType == field.entityName }) {
            tableName = reg.tableName
        } else {
            // Fallback : construit le nom depuis le namespace + entityName
            tableName = "\(namespace)_\(field.entityName.lowercased())s"
        }

        // 2. Nom de colonne : camelCase → snake_case
        let columnName = SQLiteSchemaBuilder.camelToSnake(field.fieldName)

        // 3. Type SQL : inféré depuis la valeur par défaut
        let sqlType = inferSQLType(from: field.defaultValue)

        return SQLiteAddColumnMigration(
            from:    field.fromVersion,
            to:      field.toVersion,
            table:   tableName,
            column:  columnName,
            type:    sqlType,
            default: field.defaultValue
        )
    }

    /// Infère le type SQL depuis la valeur par défaut.
    ///
    /// Règles :
    ///   - "0", "1", ou tout entier   → INTEGER
    ///   - "0.0", "3.14"              → REAL
    ///   - "'some text'"              → TEXT (avec quotes = text literal)
    ///   - nil                        → TEXT (nullable, pas de default)
    ///   - "true", "false"            → INTEGER (SQLite stocke les bool en int)
    private static func inferSQLType(from defaultValue: String?) -> String {
        guard let value = defaultValue else { return "TEXT" }

        let trimmed = value.trimmingCharacters(in: .whitespaces)

        // Boolean
        if trimmed == "true" || trimmed == "false" { return "INTEGER" }

        // Integer
        if Int(trimmed) != nil { return "INTEGER" }

        // Real
        if Double(trimmed) != nil && trimmed.contains(".") { return "REAL" }

        // Text (avec ou sans quotes)
        return "TEXT"
    }
}
