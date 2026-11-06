//
//  MessageDeduplicator.swift
//  AppModules
//
//  Created by Asyst on 6/3/26.
//

// MARK: - RealtimeKit/Dedup/MessageDeduplicator.swift
//
// Module  : RealtimeKit (internal)
// Rôle    : Filtrage des messages entrants dupliqués.
//           Avec QoS 1 (at-least-once), le broker re-délivre les messages
//           s'il ne reçoit pas l'accusé à temps. Le client reçoit des doublons.
//           Sans dédup, FeatureWallet affiche deux fois la même transaction.
//
// DIFFÉRENT du DedupService de NetworkKit :
//   NetworkKit DedupService → déduplique les requêtes HTTP SORTANTES identiques
//   MessageDeduplicator     → déduplique les messages ENTRANTS reçus du broker
//
// Algorithme :
//   - Fenêtre glissante de N message IDs (OrderedDictionary : ID → timestamp)
//   - Chaque entrée a un TTL (ex: 5 minutes)
//   - Quand la fenêtre est pleine, les entrées les plus anciennes sont éjectées
//   - Nettoyage périodique des entrées expirées (lazy, à chaque check)
//
// Design  : Actor pour le thread safety (appelé depuis la receive loop du RealtimeClient).

import Foundation
import WaanguCoreKit

// MARK: - MessageDeduplicator

/// Filtre les messages entrants dupliqués via une fenêtre glissante d'IDs.
///
/// Avec QoS 1, le broker garantit "at-least-once" en re-livrant les messages
/// pour lesquels il n'a pas reçu d'accusé (PUBACK). Le client peut donc
/// recevoir le même message plusieurs fois. Le deduplicator filtre ces doublons
/// avant qu'ils n'atteignent les souscriptions des features.
///
/// ```swift
/// // Dans RealtimeClient.handleIncomingMessage() :
/// if await deduplicator.isDuplicate(messageId) {
///     // Message déjà traité → ignorer
///     return
/// }
/// await deduplicator.markSeen(messageId)
/// // Continuer le traitement...
/// ```
actor MessageDeduplicator {

    // MARK: - Storage

    /// Les IDs vus récemment, avec leur timestamp d'insertion.
    /// Ordre d'insertion préservé pour l'éviction FIFO.
    private var seenEntries: [MessageID: Date]

    /// Ordre d'insertion pour l'éviction FIFO quand la fenêtre est pleine.
    private var insertionOrder: [MessageID]

    // MARK: - Configuration

    /// Nombre maximum d'IDs dans la fenêtre.
    private let windowSize: Int

    /// Durée de rétention d'un ID (secondes).
    /// Au-delà, l'entrée est considérée expirée et peut être purgée.
    private let ttl: TimeInterval

    /// Compteur de nettoyages pour déclencher la purge périodique.
    /// La purge n'est pas faite à chaque appel (coûteux) mais toutes les N opérations.
    private var operationsSinceLastPurge: Int = 0

    /// Nombre d'opérations entre deux purges automatiques.
    private let purgeInterval: Int

    // MARK: - Stats

    /// Nombre total de doublons filtrés (pour les métriques).
    private var totalDuplicatesFiltered: Int = 0

    /// Nombre total de purges effectuées.
    private var totalPurges: Int = 0

    // MARK: - Init

    /// Crée un deduplicator avec la taille de fenêtre et le TTL donnés.
    ///
    /// - Parameters:
    ///   - windowSize: Nombre maximum d'IDs retenus. Default: 1000.
    ///   - ttl: Durée de rétention en secondes. Default: 300 (5 minutes).
    ///   - purgeInterval: Nombre d'opérations entre deux purges auto. Default: 100.
    init(
        windowSize: Int = 1000,
        ttl: TimeInterval = 300,
        purgeInterval: Int = 100
    ) {
        self.windowSize = max(windowSize, 1)
        self.ttl = ttl
        self.purgeInterval = max(purgeInterval, 1)
        self.seenEntries = [:]
        self.insertionOrder = []
        self.seenEntries.reserveCapacity(windowSize)
        self.insertionOrder.reserveCapacity(windowSize)
    }

    // MARK: - Public API

    /// Vérifie si un message a déjà été vu.
    ///
    /// Retourne `true` si l'ID est dans la fenêtre et n'est pas expiré.
    /// Déclenche une purge périodique des entrées expirées.
    ///
    /// - Parameter id: L'ID du message à vérifier.
    /// - Returns: `true` si le message est un doublon.
    func isDuplicate(_ id: MessageID) -> Bool {
        triggerPeriodicPurgeIfNeeded()

        guard let seenAt = seenEntries[id] else {
            return false
        }

        // Vérifier si l'entrée est encore valide (pas expirée).
        if Date().timeIntervalSince(seenAt) > ttl {
            // Expirée → retirer et considérer comme nouveau.
            removeEntry(id)
            return false
        }

        totalDuplicatesFiltered += 1
        return true
    }

    /// Marque un message comme vu.
    ///
    /// L'ID est ajouté à la fenêtre avec le timestamp courant.
    /// Si la fenêtre est pleine, l'entrée la plus ancienne est éjectée.
    ///
    /// - Parameter id: L'ID du message à marquer.
    func markSeen(_ id: MessageID) {
        let now = Date()

        // Si l'ID est déjà présent, mettre à jour le timestamp.
        if seenEntries[id] != nil {
            seenEntries[id] = now
            return
        }

        // Éjecter les entrées les plus anciennes si la fenêtre est pleine.
        while insertionOrder.count >= windowSize {
            evictOldest()
        }

        // Insérer la nouvelle entrée.
        seenEntries[id] = now
        insertionOrder.append(id)
    }

    /// Vide complètement la fenêtre.
    ///
    /// Utile au reset ou à la déconnexion.
    func clear() {
        seenEntries.removeAll()
        insertionOrder.removeAll()
    }

    /// Nombre d'entrées actuellement dans la fenêtre.
    var count: Int {
        seenEntries.count
    }

    /// Nombre total de doublons filtrés depuis la création.
    var duplicatesFilteredCount: Int {
        totalDuplicatesFiltered
    }

    // MARK: - Diagnostics

    /// Snapshot de l'état courant (pour les métriques et le debugging).
    struct Snapshot: Sendable {
        let currentSize: Int
        let windowSize: Int
        let ttl: TimeInterval
        let duplicatesFiltered: Int
        let purgesPerformed: Int
        let fillPercentage: Double
    }

    /// Retourne un snapshot de l'état courant.
    func snapshot() -> Snapshot {
        Snapshot(
            currentSize: seenEntries.count,
            windowSize: windowSize,
            ttl: ttl,
            duplicatesFiltered: totalDuplicatesFiltered,
            purgesPerformed: totalPurges,
            fillPercentage: Double(seenEntries.count) / Double(windowSize) * 100
        )
    }

    // MARK: - Private — Eviction

    /// Éjecte l'entrée la plus ancienne (FIFO).
    private func evictOldest() {
        guard let oldestId = insertionOrder.first else { return }
        removeEntry(oldestId)
    }

    /// Retire une entrée par son ID.
    private func removeEntry(_ id: MessageID) {
        seenEntries.removeValue(forKey: id)
        if let index = insertionOrder.firstIndex(of: id) {
            insertionOrder.remove(at: index)
        }
    }

    // MARK: - Private — Periodic Purge

    /// Déclenche une purge des entrées expirées si le compteur le permet.
    ///
    /// La purge n'est pas faite à chaque appel pour des raisons de performance.
    /// Elle est déclenchée toutes les `purgeInterval` opérations.
    private func triggerPeriodicPurgeIfNeeded() {
        operationsSinceLastPurge += 1
        guard operationsSinceLastPurge >= purgeInterval else { return }
        purgeExpired()
    }

    /// Retire toutes les entrées dont le TTL est dépassé.
    private func purgeExpired() {
        operationsSinceLastPurge = 0
        totalPurges += 1

        let now = Date()
        var expiredIds: [MessageID] = []

        for (id, seenAt) in seenEntries {
            if now.timeIntervalSince(seenAt) > ttl {
                expiredIds.append(id)
            }
        }

        for id in expiredIds {
            removeEntry(id)
        }

        #if DEBUG
        if !expiredIds.isEmpty {
            print("[RealtimeKit] Dedup purge: removed \(expiredIds.count) expired entries, \(seenEntries.count) remaining")
        }
        #endif
    }
}
