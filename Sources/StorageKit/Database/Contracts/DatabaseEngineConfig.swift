//
//  DatabaseEngineConfig.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : StorageKit                                         │
// │  FICHIER : Database/Contracts/DatabaseEngineConfig.swift     │
// │                                                              │
// │  INTERNE — paramètres de configuration transmis à chaque     │
// │  engine lors du setup() d'un namespace.                      │
// │                                                              │
// │  Chaque engine utilise ce qu'il comprend et ignore le reste. │
// │  Ex : RealmEngine ignore `storeDirectory` (Realm gère ça).  │
// │  Ex : InMemoryEngine ignore tout.                            │
// └──────────────────────────────────────────────────────────────┘

import Foundation
import WaanguCoreKit

// ─────────────────────────────────────────────────────────────
// MARK: DatabaseEngineConfig
// ─────────────────────────────────────────────────────────────

struct DatabaseEngineConfig: Sendable {

    /// Namespace concerné (redondant avec le paramètre de setup,
    /// pratique pour les logs internes à l'engine).
    let namespace: String

    /// Répertoire où l'engine stocke ses fichiers.
    /// Ignoré par les engines sans fichier (InMemory, certains Realm cloud).
    let storeDirectory: URL

    /// Clé de chiffrement at-rest. `nil` = pas de chiffrement.
    /// L'engine décide comment l'utiliser (SQLCipher, FileProtection, Realm key…).
    let encryptionKey: Data?

    /// Étapes de migration à appliquer si la version stockée est inférieure
    /// à la version actuelle du schéma. Ordonnées par fromVersion croissant.
    let migrationSteps: [any MigrationStep]

    // ── Valeur par défaut ─────────────────────────────────────

    static func `default`(namespace: String) -> Self {
        DatabaseEngineConfig(
            namespace: namespace,
            storeDirectory: .documentsDirectory
                .appending(path: "StorageKit/Database", directoryHint: .isDirectory),
            encryptionKey: nil,
            migrationSteps: []
        )
    }
}
