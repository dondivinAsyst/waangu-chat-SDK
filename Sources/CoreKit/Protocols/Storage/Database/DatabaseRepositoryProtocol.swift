//
//  DatabaseRepositoryProtocol.swift
//  AppModules
//
//  Created by Asyst on 5/16/26.
//

// ┌──────────────────────────────────────────────────────────────┐
// │  MODULE  : CoreKit                                           │
// │  FICHIER : Database/DatabaseRepositoryProtocol.swift         │
// │                                                              │
// │  Contrat unique utilisé par toutes les features.             │
// │  Actor-isolated → thread-safe par construction Swift.        │
// │  Jamais instancié dans une feature : toujours injecté        │
// │  par DependencyContainer depuis le App Target.               │
// └──────────────────────────────────────────────────────────────┘

import Foundation

// ─────────────────────────────────────────────────────────────
// MARK: DatabaseRepositoryProtocol
// ─────────────────────────────────────────────────────────────

public protocol DatabaseRepositoryProtocol: Actor {

    // ── Écriture ──────────────────────────────────────────────

    /// Sauvegarde une entité (insert ou update si l'id existe déjà).
    func save<T: Storable>(_ entity: T) async throws

    /// Sauvegarde un lot d'entités en une seule opération.
    /// Préférer cette méthode pour les volumes > 10 entités.
    func saveAll<T: Storable>(_ entities: [T]) async throws

    // ── Lecture ───────────────────────────────────────────────

    /// Récupère toutes les entités correspondant à la requête.
    /// `query: nil` retourne toutes les entités du type dans le namespace.
    func fetch<T: Storable>(_ type: T.Type, query: QuerySpec?) async throws -> [T]

    /// Récupère une entité par son identifiant.
    /// Retourne `nil` si elle n'existe pas (ne throw pas).
    func fetchOne<T: Storable>(_ type: T.Type, id: T.ID) async throws -> T?

    /// Nombre d'entités correspondant à la requête.
    func count<T: Storable>(_ type: T.Type, query: QuerySpec?) async throws -> Int

    // ── Suppression ───────────────────────────────────────────

    /// Supprime l'entité identifiée par `id`.
    /// Throw `DatabaseError.notFound` si elle n'existe pas.
    func delete<T: Storable>(_ type: T.Type, id: T.ID) async throws

    /// Supprime toutes les entités correspondant à la requête.
    /// `query: nil` supprime toutes les entités du type dans le namespace.
    func deleteAll<T: Storable>(_ type: T.Type, query: QuerySpec?) async throws

    // ── Transactions ──────────────────────────────────────────

    /// Exécute `block` de façon atomique.
    /// Si `block` throw, toutes les modifications sont annulées (rollback).
    ///
    /// Sur le store SQLite, une vraie transaction (B51) : les autres tâches
    /// attendent sa fin. Le bloc ne doit donc pas *attendre* une tâche détachée
    /// qui écrit dans la même base — elle attendrait la transaction, qui
    /// l'attendrait.
    ///
    /// ```swift
    /// try await db.withTransaction {
    ///     try await db.save(message)
    ///     try await db.save(receipt)
    ///     // Si l'un échoue → les deux sont annulés
    /// }
    /// ```
    func withTransaction<R: Sendable>(
        _ block: @Sendable () async throws -> R
    ) async throws -> R

    // ── Observation réactive ──────────────────────────────────

    /// Retourne un flux qui émet à chaque modification des entités
    /// correspondant à la requête dans le namespace de `T`.
    /// Le flux émet une première valeur immédiatement (état initial).
    ///
    /// ```swift
    /// for await result in db.observe(Message.self, query: nil) {
    ///     switch result {
    ///     case .success(let messages): render(messages)
    ///     case .failure(let error):   handle(error)
    ///     }
    /// }
    /// ```
    func observe<T: Storable>(
        _ type: T.Type,
        query: QuerySpec?
    ) -> AsyncStream<Result<[T], DatabaseError>>

    // ── Maintenance ───────────────────────────────────────────

    /// Supprime toutes les données du namespace sans le désinstaller.
    /// Usage : déconnexion utilisateur, reset onboarding.
    func clearAll(namespace: String) async throws
}
