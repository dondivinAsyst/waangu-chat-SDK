//
//  FeatureSyncEngine 2.swift
//  Waangu
//
//  Created by Asyst on 6/19/26.
//


// MARK: - AppTarget/Sync/FeatureSyncEngine.swift
//
// Module  : App Target
// Rôle    : Moteur de synchro générique — écrit UNE FOIS, utilisé par chaque feature.
//
// Architecture :
//   SyncCoordinator
//     │ appelle FeatureSyncProtocol (flushOutbox, pullMissedEvents, stopSync)
//     ↓
//   FeatureSyncEngine<D: SyncDelegate>  ← CE FICHIER
//     │ délègue au SyncDelegate (fetchPage, processEvent, pullInboxSummary)
//     ↓
//   ChatSyncDelegate / WalletSyncDelegate  ← logique métier par feature
//
// Le moteur gère :
//   - Flush outbox (montant : client → serveur)
//   - Pull paginé (descendant : serveur → client, 3 phases)
//   - Realtime live (MQTT → database)
//   - Crash recovery (SyncState persisté, cursor sauvegardé)
//   - Pacing adaptatif (pause entre les pages)

import Foundation
import WaanguCoreKit

// MARK: - FeatureSyncEngine

public actor FeatureSyncEngine<D: SyncDelegate>: FeatureSyncProtocol {

    // MARK: - Identity

    public nonisolated var featureName: String { delegate.featureName }
    public nonisolated let syncPriority: SyncPriority

    // MARK: - Dependencies

    private let delegate: D
    private let outbox: any OutboxFlushing
    private let apiClient: any APIClientProtocol
    private let database: any DatabaseRepositoryProtocol
    private let realtime: any RealtimeClientProtocol
    private let pullConfig: SyncEngineConfiguration
    /// Compte de la session courante. Injecté : le moteur ne connaît aucune feature.
    /// Par défaut le propriétaire est constant : le garde de changement de compte ne se
    /// déclenche jamais. Toute feature qui a des comptes doit fournir le sien.
    private let currentOwner: @Sendable () -> String
    /// Phase 4 (abonnement live). Faux quand la feature tient déjà son propre flux live :
    /// le Chat garde le sien (`ChatFeature`), un second appliquerait chaque événement deux fois.
    private let liveUpdates: Bool

    // MARK: - State

    private var realtimeTask: Task<Void, Never>?
    private var pullTask: Task<Void, Never>?
    private var subscriptionToken: RealtimeSubscriptionToken?
    /// Un pull est en cours (phases 1 à 3). Un événement live refusé pendant ce temps
    /// demande un nouveau passage au lieu d'en lancer un second en parallèle.
    private var pullInFlight = false
    private var repullRequested = false
    /// Repère de synchro d'avant l'événement refusé : le pull en cours va avancer le sien au-delà.
    private var repullFloor: Date?

    // MARK: - Init

    public init(
        delegate: D,
        outbox: any OutboxFlushing,
        apiClient: any APIClientProtocol,
        database: any DatabaseRepositoryProtocol,
        realtime: any RealtimeClientProtocol,
        syncPriority: SyncPriority,
        pullConfig: SyncEngineConfiguration = .default,
        currentOwner: @escaping @Sendable () -> String = { "" },
        liveUpdates: Bool = true
    ) {
        self.delegate = delegate
        self.outbox = outbox
        self.apiClient = apiClient
        self.database = database
        self.realtime = realtime
        self.syncPriority = syncPriority
        self.pullConfig = pullConfig
        self.currentOwner = currentOwner
        self.liveUpdates = liveUpdates
    }

    // MARK: - FeatureSyncProtocol

    public func flushOutbox() async {
        let results = await outbox.flush()
        let synced = results.filter(\.success).count

        if !results.isEmpty {
            await delegate.didFlush(results: results, database: database)

            #if DEBUG
            print("[SyncEngine:\(featureName)] Flushed \(synced) items")
            #endif
        }
    }

    public func pullMissedEvents() async {
        pullInFlight = true
        defer { pullInFlight = false }

        // Charger l'état de synchro (cursor sauvegardé si interruption)
        var syncState = await loadSyncState()
        syncState.isSyncing = true
        await saveSyncState(syncState)

        // Le compte qui lance cette synchro (F-09) : `stopSync()` annule les tâches mais
        // n'arrête pas une page déjà reçue ; sans ce repère, elle s'appliquerait à la
        // base du compte suivant et laisserait derrière elle le curseur du précédent.
        let owner = currentOwner()

        // Phase 1 — Inbox summary (rapide, critique pour l'UX)
        let hasSummary = await delegate.pullInboxSummary(
            apiClient: apiClient,
            database: database
        )

        #if DEBUG
        if hasSummary {
            print("[SyncEngine:\(featureName)] Phase 1 — Inbox summary done")
        }
        #endif

        // Phase 2 — Active item (conversation ouverte, trajet actif)
        await delegate.pullActiveItem(
            apiClient: apiClient,
            database: database
        )

        #if DEBUG
        print("[SyncEngine:\(featureName)] Phase 2 — Active item done")
        #endif

        // Phase 3 — Full sync paginé. Repassé tant qu'un événement live refusé en a demandé
        // un : la page qui le contient est relue depuis le dernier repère de synchro.
        repeat {
            repullRequested = false
            if let floor = repullFloor {
                repullFloor = nil
                syncState.lastSyncTimestamp = floor
                syncState.currentCursor = nil
            }
            await runPaginatedPull(&syncState, owner: owner)
        } while repullRequested && !Task.isCancelled && currentOwner() == owner

        // Phase 4 — Realtime live
        if liveUpdates {
            await startRealtimeSync(owner: owner)
        }
    }

    public func stopSync() async {
        // Annuler les tasks en cours
        pullTask?.cancel()
        pullTask = nil
        realtimeTask?.cancel()
        realtimeTask = nil

        // Libérer la souscription MQTT
        await subscriptionToken?.cancel()
        subscriptionToken = nil

        // Marquer la synchro comme arrêtée
        var syncState = await loadSyncState()
        syncState.isSyncing = false
        await saveSyncState(syncState)

        #if DEBUG
        print("[SyncEngine:\(featureName)] Sync stopped")
        #endif
    }

    public func isDegraded() async -> Bool {
        await loadSyncState().isDegraded
    }

    // MARK: - Private — Phase 3 : Pull paginé

    private func runPaginatedPull(_ syncState: inout SyncState, owner: String) async {
        var cursor = syncState.currentCursor
        // Sans curseur enregistré, `cursor == nil` vaut aussi pour une première page qui a
        // échoué ou une tâche annulée : seule une page reçue jusqu'au bout clôt la synchro (F-11).
        var interrupted = false

        repeat {
            guard !Task.isCancelled else { interrupted = true; break }

            do {
                let page = try await delegate.fetchPage(
                    since: syncState.lastSyncTimestamp,
                    cursor: cursor,
                    limit: pullConfig.pullPageSize,
                    apiClient: apiClient
                )

                // Traiter chaque événement — tant que le compte est le même. On sort
                // sans toucher au curseur ni marquer la synchro complète : l'état
                // enregistré n'est plus celui de cette session.
                guard currentOwner() == owner else { return }
                for (index, event) in page.events.enumerated() {
                    guard currentOwner() == owner else { return }
                    // N-02 : un événement dont l'écriture a été refusée n'est pas stocké ;
                    // le curseur ne doit pas le dépasser. La page sera relue au prochain
                    // passage (les écritures sont idempotentes). On ne saute pas l'événement :
                    // le perdre en silence est pire que de réessayer.
                    if case .failed(let reason) = await delegate.applyEvent(event, database: database) {
                        // Réessai borné : on compte les passages ratés sur ce même événement
                        // (retrouvé par sa page de départ et son rang). Au-delà du seuil la
                        // synchro est signalée dégradée (`SyncState.isDegraded`), jamais sautée.
                        let key = "\(syncState.currentCursor ?? "start")#\(index)"
                        let attempts = syncState.blockedEventKey == key ? (syncState.blockedAttempts ?? 0) + 1 : 1
                        syncState.blockedEventKey = key
                        syncState.blockedAttempts = attempts
                        syncState.blockedReason = reason
                        await saveSyncState(syncState)
                        #if DEBUG
                        print("[SyncEngine:\(featureName)] Event \(key) refused (attempt \(attempts)): \(reason)")
                        #endif
                        interrupted = true
                        break
                    }
                }
                if interrupted { break }
                if syncState.blockedEventKey != nil {
                    syncState.blockedEventKey = nil
                    syncState.blockedAttempts = nil
                    syncState.blockedReason = nil
                }

                cursor = page.nextCursor

                // Sauvegarder le cursor pour reprise après interruption
                syncState.currentCursor = cursor
                await saveSyncState(syncState)

                #if DEBUG
                print("[SyncEngine:\(featureName)] Phase 3 — Page done (\(page.events.count) events, hasMore: \(page.hasMore))")
                #endif

                // Pause entre les pages
                if page.hasMore && pullConfig.interPageDelay > 0 {
                    try await Task.sleep(
                        nanoseconds: UInt64(pullConfig.interPageDelay * 1_000_000_000)
                    )
                }

            } catch {
                // Réseau coupé — on reprendra avec le cursor sauvegardé
                #if DEBUG
                print("[SyncEngine:\(featureName)] Phase 3 — Pull interrupted: \(error.localizedDescription)")
                #endif
                interrupted = true
                break
            }
        } while cursor != nil

        // Synchro complète — mettre à jour le timestamp
        if cursor == nil && !interrupted {
            syncState.lastSyncTimestamp = Date()
            syncState.currentCursor = nil
            syncState.isSyncing = false
            await saveSyncState(syncState)

            #if DEBUG
            print("[SyncEngine:\(featureName)] Phase 3 — Full sync complete")
            #endif
        }
    }

    // MARK: - Private — Phase 4 : Realtime live

    private func startRealtimeSync(owner: String) async {
        realtimeTask?.cancel()
        await subscriptionToken?.cancel()

        realtimeTask = Task { [weak self] in
            guard let self else { return }
            await self.runRealtimeLoop(owner: owner)
        }
    }

    private func runRealtimeLoop(owner: String) async {
        do {
            guard let sync = try await delegate.realtimeSubscription(
                realtime: realtime
            ) else {
                // La feature n'a pas de synchro live (ex: marketplace catalogue)
                return
            }

            subscriptionToken = sync.token

            for await event in sync.stream {
                guard !Task.isCancelled, currentOwner() == owner else { break }
                // N-02 : un événement live dont l'écriture est refusée n'est pas stocké. On le
                // fait relire par un pull plutôt que de le tenir pour appliqué.
                if case .failed(let reason) = await delegate.applyEvent(event, database: database) {
                    #if DEBUG
                    print("[SyncEngine:\(featureName)] Live event refused: \(reason)")
                    #endif
                    await recoverAfterRefusedLiveEvent(owner: owner)
                }
            }
        } catch {
            #if DEBUG
            print("[SyncEngine:\(featureName)] Realtime sync error: \(error.localizedDescription)")
            #endif
        }
    }

    /// Relit les événements manqués après un événement live refusé. Si un pull tourne déjà,
    /// il fera un passage de plus ; sinon on lance la phase 3 seule (pas de nouvel abonnement
    /// live : cette tâche en est justement la boucle).
    private func recoverAfterRefusedLiveEvent(owner: String) async {
        guard currentOwner() == owner else { return }
        if pullInFlight {
            repullRequested = true
            if repullFloor == nil {
                // Sans repère enregistré (première synchro), on repart de l'origine.
                repullFloor = (await loadSyncState()).lastSyncTimestamp ?? Date(timeIntervalSince1970: 0)
            }
            return
        }
        pullInFlight = true
        defer { pullInFlight = false }
        var syncState = await loadSyncState()
        await runPaginatedPull(&syncState, owner: owner)
    }

    // MARK: - Private — SyncState persistence

    private func loadSyncState() async -> SyncState {
        (try? await database.fetchOne(SyncState.self, id: featureName)) 
            ?? SyncState(feature: featureName)
    }

    private func saveSyncState(_ state: SyncState) async {
        try? await database.save(state)
    }
}
