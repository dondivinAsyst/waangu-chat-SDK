//
//  Migrationstep.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : CoreKit                                            │
// │  FICHIER : Database/MigrationStep.swift                      │
// │                                                              │
// │  Contrat d'une étape de migration.                           │
// │                                                              │
// │  Ce que CoreKit sait : il existe des migrations versionnées  │
// │  avec un numéro source, un numéro cible, et une description. │
// │                                                              │
// │  Ce que CoreKit ne sait PAS :                                │
// │  - Comment valider la migration (pas de contexte ici)        │
// │  - Comment l'exécuter (pas de SQL, pas de NSMappingModel)    │
// │  - Quel engine est utilisé                                   │
// │                                                              │
// │  StorageKit raffine ce protocol avec un contexte engine      │
// │  concret (SwiftDataMigrationStep, CoreDataMigrationStep…).   │
// └──────────────────────────────────────────────────────────────┘

import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: MigrationStep
// ─────────────────────────────────────────────────────────────

/// Décrit une étape de migration de schéma.
///
/// Déclaré dans CoreKit pour permettre à `DatabaseAssembly.Config`
/// (StorageKit) d'accepter `[any MigrationStep]` sans que l'App Target
/// n'ait à importer StorageKit pour typer ses migrations.
///
/// Les méthodes concrètes (validate, perform, rollback) sont définies
/// dans les raffinements de StorageKit, car elles reçoivent un contexte
/// spécifique à l'engine (SQL, NSManagedObjectContext, Realm…).
public protocol MigrationStep: Sendable {

    /// Version de départ. Ex : 1
    var fromVersion: Int { get }

    /// Version cible. Ex : 2
    var toVersion: Int { get }

    /// Description lisible, pour les logs et les diagnostics.
    var description: String { get }
}
