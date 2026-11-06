//
//  DatabaseError.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : CoreKit                                            │
// │  FICHIER : Database/DatabaseError.swift                      │
// │                                                              │
// │  Erreurs retournées par DatabaseRepositoryProtocol.          │
// │  Indépendantes de l'engine : une feature ne sait pas         │
// │  si l'erreur vient de CoreData, SwiftData, Realm ou SQLite.  │
// └──────────────────────────────────────────────────────────────┘

import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: DatabaseError
// ─────────────────────────────────────────────────────────────

public enum DatabaseError: Error, Sendable {

    // ── CRUD ──────────────────────────────────────────────────
    /// L'entité demandée n'existe pas dans le namespace.
    case notFound(id: String, type: String, namespace: String)

    /// Échec d'une opération d'écriture.
    case writeFailed(namespace: String, underlying: Error)

    /// Échec d'une opération de lecture.
    case readFailed(namespace: String, underlying: Error)

    // ── Intégrité ─────────────────────────────────────────────
    /// Données impossibles à décoder : schéma incohérent.
    case corruptedData(namespace: String, details: String)

    // ── Transactions ──────────────────────────────────────────
    /// La transaction a échoué et a été rollback.
    case transactionFailed(underlying: Error)

    /// Tentative d'imbriquer deux transactions sur le même namespace.
    case transactionAlreadyActive(namespace: String)

    // ── Migrations ────────────────────────────────────────────
    /// Le dry-run a rejeté la migration avant même de commencer.
    case migrationDryRunFailed(namespace: String, fromVersion: Int, toVersion: Int, reason: String)

    /// La migration a démarré mais a échoué. Le backup a été restauré.
    case migrationFailed(namespace: String, fromVersion: Int, toVersion: Int, underlying: Error)

    // ── Chiffrement ───────────────────────────────────────────
    /// Impossible de lire ou d'écrire la clé de chiffrement.
    case encryptionFailed(underlying: Error)

    // ── Infrastructure ────────────────────────────────────────
    /// Le namespace demandé n'a pas encore été initialisé.
    case namespaceNotReady(String)

    /// L'engine n'est pas disponible (ex. : iOS trop ancien pour SwiftData).
    case engineUnavailable(reason: String)
}

// ─────────────────────────────────────────────────────────────
// MARK: LocalizedError
// ─────────────────────────────────────────────────────────────

extension DatabaseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notFound(let id, let type, let ns):
            return "[\(ns)] \(type) introuvable — id: \(id)"
        case .writeFailed(let ns, let err):
            return "[\(ns)] Écriture échouée : \(err.localizedDescription)"
        case .readFailed(let ns, let err):
            return "[\(ns)] Lecture échouée : \(err.localizedDescription)"
        case .corruptedData(let ns, let details):
            return "[\(ns)] Données corrompues : \(details)"
        case .transactionFailed(let err):
            return "Transaction échouée (rollback effectué) : \(err.localizedDescription)"
        case .transactionAlreadyActive(let ns):
            return "[\(ns)] Transaction déjà active sur ce namespace"
        case .migrationDryRunFailed(let ns, let from, let to, let reason):
            return "[\(ns)] Migration v\(from)→v\(to) refusée : \(reason)"
        case .migrationFailed(let ns, let from, let to, let err):
            return "[\(ns)] Migration v\(from)→v\(to) échouée : \(err.localizedDescription)"
        case .encryptionFailed(let err):
            return "Chiffrement échoué : \(err.localizedDescription)"
        case .namespaceNotReady(let ns):
            return "Namespace '\(ns)' non initialisé"
        case .engineUnavailable(let reason):
            return "Engine indisponible : \(reason)"
        }
    }
}
