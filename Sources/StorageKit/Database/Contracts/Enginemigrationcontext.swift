//
//  Enginemigrationcontext.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/Contracts/EngineMigrationContext.swift   │
// │                                                              │
// │  INTERNE — raffinements de MigrationStep (CoreKit).          │
// │                                                              │
// │  Hiérarchie :                                                │
// │    CoreKit         → MigrationStep (pas de méthodes)         │
// │    StorageKit      → EngineCapableMigrationStep              │
// │                       + EngineMigrationContext (opaque)      │
// │    Par engine      → SwiftDataMigrationStep                  │
// │                       + SwiftDataMigrationContext (concret)  │
// │                      CoreDataMigrationStep                   │
// │                       + CoreDataMigrationContext (concret)   │
// │                      RealmMigrationStep + …                  │
// │                                                              │
// │  MigrationManager ne connaît que EngineCapableMigrationStep  │
// │  et EngineMigrationContext — jamais les types concrets.      │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: EngineMigrationContext
// ─────────────────────────────────────────────────────────────

/// Contexte opaque fourni par un engine à ses propres étapes.
/// MigrationManager le reçoit, le stocke, le transmet — jamais l'inspecte.
/// Chaque engine fournit une implémentation concrète
/// (SwiftDataMigrationContext, CoreDataMigrationContext, RealmMigrationContext…).
protocol EngineMigrationContext: Sendable {
    var namespace: String { get }
}

// ─────────────────────────────────────────────────────────────
// MARK: EngineCapableMigrationStep
// ─────────────────────────────────────────────────────────────

/// Raffinement de MigrationStep (CoreKit) avec les méthodes d'exécution.
/// Les méthodes reçoivent `any EngineMigrationContext` — MigrationManager
/// appelle ces méthodes sans savoir quel contexte concret est dedans.
/// Chaque famille d'engine raffine encore en acceptant son propre contexte
/// typé (SwiftDataMigrationStep, CoreDataMigrationStep…).
protocol EngineCapableMigrationStep: MigrationStep {

    /// Valide sans rien modifier. Throw = dry-run refusé, migration annulée.
    func validate(in context: any EngineMigrationContext) async throws

    /// Exécute la migration. Appelé uniquement si validate() a réussi.
    func perform(in context: any EngineMigrationContext) async throws

    /// Annule les effets partiels si perform() a échoué à mi-chemin.
    /// MigrationManager restaure aussi le backup fichier après rollback.
    func rollback(in context: any EngineMigrationContext) async throws
}
