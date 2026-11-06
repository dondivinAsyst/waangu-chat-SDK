//
//  DatabaseAssembly.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                        │
// │  FICHIER : Database/DatabaseAssembly.swift                   │
// │  PUBLIC — seul symbole que le App Target utilise.            │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import WaanguCoreKit

public enum DatabaseAssembly {

    // ─────────────────────────────────────────────────────────
    // MARK: Config
    // ─────────────────────────────────────────────────────────

    public struct Config {
        public let engine:               EngineOption
        public let slowQueryThresholdMs: Int
        public let metricsDelegate:      (any DatabaseMetricsDelegate)?
        public let migrationSteps:       [any MigrationStep]

        public init(
            engine:               EngineOption = .coreData,
            slowQueryThresholdMs: Int = 16,
            metricsDelegate:      (any DatabaseMetricsDelegate)? = nil,
            migrationSteps:       [any MigrationStep] = []
        ) {
            self.engine               = engine
            self.slowQueryThresholdMs = slowQueryThresholdMs
            self.metricsDelegate      = metricsDelegate
            self.migrationSteps       = migrationSteps
        }
    }

    public enum EngineOption {
        case coreData
        case swiftData
        case sqlite
        case realm
        case inMemory
    }

    // ─────────────────────────────────────────────────────────
    // MARK: make — store standard
    // ─────────────────────────────────────────────────────────

    public static func make(config: Config = Config()) -> any DatabaseRepositoryProtocol {
        let engine: any DatabaseEngine = switch config.engine {
        case .coreData:  CoreDataEngine()
        case .swiftData: SwiftDataEngine()
        case .sqlite:    SQLiteEngine()
        case .realm:     RealmEngine()
        case .inMemory:  InMemoryEngine()
        }
        return DatabaseStore(
            engine:             engine,
            slowQueryThreshold: .milliseconds(config.slowQueryThresholdMs),
            metricsDelegate:    config.metricsDelegate
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: makeSearchable — store SQLite avec FTS5 + relations
    // ─────────────────────────────────────────────────────────
    // La config (migrationSteps inclus) est passée via le paramètre
    // config et transmise à l'engine lors du setup() de chaque namespace.
    // L'engine SQLite est créé ici et réutilisé pour les register().

    public static func makeSearchable(config: Config = Config()) -> any SearchableDatabaseProtocol {
        let sqliteEngine = SQLiteEngine()
        let baseConfig   = DatabaseEngineConfig(
            namespace:      "",    // remplacé par le namespace réel dans ensureReady()
            storeDirectory: .documentsDirectory
                .appending(path: "StorageKit/Database", directoryHint: .isDirectory),
            encryptionKey:  nil,
            migrationSteps: config.migrationSteps
        )
        return DatabaseStore(
            engine:             sqliteEngine,
            slowQueryThreshold: .milliseconds(config.slowQueryThresholdMs),
            metricsDelegate:    config.metricsDelegate,
            sharedConfig:       baseConfig          // ← transmis via init, pas de mutation
        )
    }

    // ─────────────────────────────────────────────────────────
    // MARK: register — enregistre les entités d'une feature
    // ─────────────────────────────────────────────────────────
    // DOIT être appelé dans bootstrap() AVANT le premier accès
    // au namespace de l'entité.
    // L'app ne référence jamais les types Storable internes aux features —
    // uniquement le DatabaseRegistrable public de chaque module.

    public static func register<R: DatabaseRegistrable>(
        _ registration: R.Type,
        in store: any SearchableDatabaseProtocol
    ) async {
        for type in registration.storableTypes {
            debugLog("this was to be able to register entities in sqlite :  \(type)")
            await registerExistential(type, in: store)
        }
    }

    private static func registerExistential(
        _ type: any Storable.Type,
        in store: any SearchableDatabaseProtocol
    ) async {
        func registerConcrete<T: Storable>(_ type: T.Type) async {
            await register(type, in: store)
        }
        await _openExistential(type, do: registerConcrete)
    }

    private static func register<T: Storable>(
        _ type: T.Type,
        in store: any SearchableDatabaseProtocol
    ) async {
        guard let dbStore = store as? DatabaseStore else { return }
        await dbStore.registerSQLiteStorable(type)
    }
}
