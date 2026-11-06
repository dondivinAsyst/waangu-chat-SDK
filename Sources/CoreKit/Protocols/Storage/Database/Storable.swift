//
//  DatabaseRepositoryProtocol.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

import Foundation

public protocol Storable: Codable, Identifiable, Sendable  {
    static var namespace:     String { get }
    static var schemaVersion: Int    { get }
    
  

    /// Champs à indexer pour les filtres et jointures rapides.
    /// Chaque engine décide comment les utiliser :
    ///   SQLiteEngine  → colonnes SQL indexées
    ///   CoreDataEngine → NSFetchIndexDescription
    ///   RealmEngine   → indexedProperties
    ///   InMemoryEngine → ignoré
    static var indexedFields: [String] { get }

    /// Champs à indexer pour la recherche full-text.
    ///   SQLiteEngine  → table FTS5
    ///   CoreDataEngine → ignoré (non supporté)
    ///   InMemoryEngine → ignoré
    static var searchableFields: [String] { get }

    /// Relations vers d'autres entités.
    ///   SQLiteEngine  → FOREIGN KEY + ON DELETE CASCADE
    ///   CoreDataEngine → ignoré (pas de relations dans le proxy)
    ///   InMemoryEngine → ignoré
    static var foreignKeys: [StorableForeignKey] { get }
}

// Valeurs par défaut — les entités simples ne déclarent rien
public extension Storable {
    static var schemaVersion:   Int                  { 1 }
    static var indexedFields:   [String]             { [] }
    static var searchableFields:[String]             { [] }
    static var foreignKeys:     [StorableForeignKey] { [] }

    static var sqliteTableName: String {
        "\(namespace)_\(String(describing: Self.self).lowercased())s"
    }
}
