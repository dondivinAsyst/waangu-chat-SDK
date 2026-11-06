//
//  SyncDelegate.swift
//  AppModules
//
//  Created by Asyst on 6/18/26.
//

import Foundation

// MARK: - Sync Delegate

/// Contrat que chaque feature implémente pour personnaliser le sync engine.
/// Le engine (App Target) gère la mécanique (pagination, cursor, lifecycle).
/// Le delegate fournit la logique métier (endpoints, mapping, processing).
///
/// Méthodes obligatoires :
///   - `featureName` — identifiant pour le logging et la persistence
///   - `fetchPage(...)` — appel HTTP paginé
///   - `processEvent(...)` — mapping DTO → domain → database
///
public protocol SyncDelegate<SyncEvent>: Sendable {

    /// Type des événements de synchro reçus du serveur (pull HTTP et MQTT live).
    associatedtype SyncEvent: Codable & Sendable

    /// Identifiant de la feature pour le logging et la persistence du SyncState.
    var featureName: String { get }

    /// Phase 1 — Inbox summary : résumé rapide de l'état serveur.
    /// Ex chat : conversations avec lastMessage + unreadCount.
    /// Ex wallet : solde courant.
    /// Retourne `true` si des données ont été récupérées.
    func pullInboxSummary(
        apiClient: any APIClientProtocol,
        database: any DatabaseRepositoryProtocol
    ) async -> Bool

    /// Phase 2 — Active item : synchro prioritaire de l'élément en cours.
    /// Ex chat : dernière conversation ouverte.
    /// Ex ride : trajet actif.
    func pullActiveItem(
        apiClient: any APIClientProtocol,
        database: any DatabaseRepositoryProtocol
    ) async

    /// Phase 3 — Page de synchro complète.
    /// Le engine gère la boucle de pagination, le delegate fournit l'appel HTTP.
    func fetchPage(
        since: Date?,
        cursor: String?,
        limit: Int,
        apiClient: any APIClientProtocol
    ) async throws -> SyncPage<SyncEvent>

    /// Traite un événement de synchro — même logique pour pull HTTP et MQTT live.
    /// Le delegate mappe le DTO vers le domain model et le persiste.
    func processEvent(
        _ event: SyncEvent,
        database: any DatabaseRepositoryProtocol
    ) async

    /// Topic realtime pour le live sync.
    /// Retourne `nil` si la feature n'a pas de synchro live.
    /// Comme ``processEvent(_:database:)``, mais dit si l'événement a vraiment été écrit.
    ///
    /// `processEvent` ne rend rien : une écriture refusée par la base y est avalée, et le
    /// moteur avançait quand même son curseur au-delà d'un événement jamais stocké. Le pull
    /// paginé passe par cette méthode et s'arrête au premier `.failed`.
    ///
    /// Défaut : `.applied`, pour qu'un délégué existant continue de compiler. Un délégué dont
    /// les écritures peuvent échouer doit la surcharger.
    func applyEvent(
        _ event: SyncEvent,
        database: any DatabaseRepositoryProtocol
    ) async -> SyncApplyOutcome

    func realtimeSubscription(
        realtime: any RealtimeClientProtocol
    ) async throws -> RealtimeSync<SyncEvent>?

    /// Callback post-flush pour mettre à jour les statuts métier.
    /// Ex chat : messages .pending → .synced.
    func didFlush(
        results: [OutboxFlushResult],
        database: any DatabaseRepositoryProtocol
    ) async
}

// MARK: - Default Implementations

public extension SyncDelegate {

    func applyEvent(
        _ event: SyncEvent,
        database: any DatabaseRepositoryProtocol
    ) async -> SyncApplyOutcome {
        await processEvent(event, database: database)
        return .applied
    }

    func pullInboxSummary(
        apiClient: any APIClientProtocol,
        database: any DatabaseRepositoryProtocol
    ) async -> Bool { false }

    func pullActiveItem(
        apiClient: any APIClientProtocol,
        database: any DatabaseRepositoryProtocol
    ) async {}

    func realtimeSubscription(
        realtime: any RealtimeClientProtocol
    ) async throws -> RealtimeSync<SyncEvent>? { nil }

    func didFlush(
        results: [OutboxFlushResult],
        database: any DatabaseRepositoryProtocol
    ) async {}
}

// MARK: - Realtime Sync Result

/// Résultat de la souscription realtime retourné par le delegate.
public struct RealtimeSync<Event: Codable & Sendable>: Sendable {
    public let stream: AsyncStream<Event>
    public let token: RealtimeSubscriptionToken

    public init(stream: AsyncStream<Event>, token: RealtimeSubscriptionToken) {
        self.stream = stream
        self.token = token
    }
}

// MARK: - Apply Outcome

/// Résultat de l'application d'un événement de synchro.
public enum SyncApplyOutcome: Sendable, Equatable {
    /// Aucune écriture n'a été refusée par la base.
    case applied
    /// Au moins une écriture a échoué. Le curseur ne doit pas passer cet événement.
    case failed(reason: String)
}
