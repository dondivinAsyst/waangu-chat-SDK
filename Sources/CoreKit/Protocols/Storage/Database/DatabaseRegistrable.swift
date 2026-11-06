//
//  DatabaseRegistrable.swift
//  AppModules
//
//  Created by Asyst on 5/19/26.
//

public protocol DatabaseRegistrable: Sendable {

    /// Les entités persistables de cette feature.
    /// Storable simple OU SQLiteStorable — la feature ne choisit pas l'engine.
    static var storableTypes: [any Storable.Type] { get }

    /// Les migrations de cette feature, dans l'ordre.
    /// MigrationStep est agnostique — CoreData, SQLite, Realm…
    /// Le DependencyContainer décide quel type de migration utiliser
    /// selon l'engine assigné à la feature.
    static var migrationSteps: [any MigrationStep] { get }
}
