//
//  SubscriptionRegistry.swift
//  AppModules
//
//  Created by Asyst on 6/3/26.
//

// MARK: - RealtimeKit/Subscriptions/SubscriptionRegistry.swift
//
// Module  : RealtimeKit (internal)
// Rôle    : Registre central de toutes les souscriptions actives.
//           Stocke les continuations type-erased, matche les messages entrants
//           vers les bonnes souscriptions (y compris wildcards), et gère
//           le throttle/debounce temporel.
//
// Design  : Actor pour le thread safety.
//           Chaque souscription est un SubscriptionEntry qui porte :
//           - Le topic (avec wildcards éventuels)
//           - La continuation type-erased (AnyContinuation)
//           - Le decoder type-erased (Data → Any)
//           - La buffering policy (pour le throttle/debounce)
//
//           Le RealtimeClient appelle subscriptions(matching:) pour chaque
//           message reçu. Le registry fait le matching (y compris wildcards)
//           et applique le throttle/debounce avant de yield.
//
// Pattern : Pas d'équivalent dans StorageKit — spécifique au temps réel.
//           En HTTP, chaque requête est indépendante. En realtime, les
//           souscriptions persistent et accumulent des listeners zombies
//           sans cleanup explicite.

import Foundation
import WaanguCoreKit
import os

/// Canal de log du registry.
///
/// Le registry peut perdre un message au flush d'un debounce (décodage
/// impossible) à un endroit où aucun `metricsDelegate` n'est accessible.
/// Perdre le message *en silence* est ce que faisait la version précédente.
private let registryLog = Logger(subsystem: "com.waangu.realtimekit", category: "subscriptions")

// MARK: - SubscriptionRegistry

/// Registre central des souscriptions temps réel actives.
///
/// Responsabilités :
/// - Stocker les souscriptions avec leurs continuations
/// - Matcher les messages entrants vers les souscriptions (wildcards inclus)
/// - Appliquer le throttle/debounce temporel
/// - Fournir des tokens de lifecycle (cancel, cleanup)
/// - Tracking par feature pour le batch cancel
actor SubscriptionRegistry {

    // MARK: - Storage

    /// Toutes les souscriptions actives, indexées par ID.
    private var entries: [UUID: SubscriptionEntry] = [:]

    /// Index inversé : topic path → [subscription IDs].
    /// Optimise le lookup au moment du dispatch (pas de scan linéaire).
    private var topicIndex: [String: Set<UUID>] = [:]

    /// Index par feature pour le batch cancel.
    private var featureIndex: [String: Set<UUID>] = [:]

    // MARK: - Init

    init() {}

    // MARK: - Register

    /// Enregistre une nouvelle souscription et retourne son token de lifecycle.
    ///
    /// - Parameters:
    ///   - topic: Le topic souscrit (peut contenir des wildcards).
    ///   - qos: Le QoS de la souscription.
    ///   - buffering: La stratégie de backpressure.
    ///   - continuation: La continuation type-erased pour yield les messages.
    ///   - decoder: Closure qui décode Data → Any (type-erased).
    /// - Returns: Un token de lifecycle pour cette souscription.
    func register(
        topic: RealtimeTopic,
        qos: RealtimeQoS,
        buffering: RealtimeBufferingPolicy,
        continuation: AnyContinuation,
        decoder: @escaping @Sendable (Data) throws -> Any
    ) -> any RealtimeSubscriptionToken {

        let id = UUID()

        let entry = SubscriptionEntry(
            id: id,
            topic: topic,
            qos: qos,
            buffering: buffering,
            continuation: continuation,
            decoder: decoder
        )

        // Stocker l'entrée.
        entries[id] = entry

        // Indexer par topic path.
        topicIndex[topic.path, default: []].insert(id)

        // Indexer par feature (si disponible).
        if let feature = topic.feature {
            featureIndex[feature.rawValue, default: []].insert(id)
        }

        // Créer le token de lifecycle.
        let token = ConcreteSubscriptionToken(
            id: id,
            topic: topic,
            feature: topic.feature?.rawValue,
            registry: self
        )

        return token
    }

    // MARK: - Remove

    /// Retire une souscription par son ID.
    ///
    /// La continuation est terminée (finish) et l'entrée est supprimée
    /// de tous les index.
    func remove(id: UUID) {
        guard let entry = entries.removeValue(forKey: id) else { return }

        // Terminer la continuation (le stream côté feature reçoit nil → fin).
        entry.continuation.finish()

        // Retirer des index.
        topicIndex[entry.topic.path]?.remove(id)
        if topicIndex[entry.topic.path]?.isEmpty == true {
            topicIndex.removeValue(forKey: entry.topic.path)
        }

        if let feature = entry.topic.feature {
            featureIndex[feature.rawValue]?.remove(id)
            if featureIndex[feature.rawValue]?.isEmpty == true {
                featureIndex.removeValue(forKey: feature.rawValue)
            }
        }
    }

    /// Annule toutes les souscriptions.
    func cancelAll() {
        let allIds = Array(entries.keys)
        for id in allIds {
            remove(id: id)
        }
    }

    // MARK: - Matching

    /// Trouve toutes les souscriptions qui matchent un topic brut reçu du transport.
    ///
    /// Gère les wildcards :
    /// - `chat/+/messages` matche `chat/abc123/messages`
    /// - `chat/#` matche `chat/abc123/messages` et `chat/abc123/presence`
    ///
    /// - Parameter rawTopic: Le topic string brut reçu du broker.
    /// - Returns: Les entrées de souscription qui matchent.
    func subscriptions(matching rawTopic: String, payload: Data) -> SubscriptionMatch {
        var results: [SubscriptionDispatch] = []
        var matchedIDs: Set<UUID> = []

        // 1. Exact match (le plus courant, O(1) via l'index).
        if let ids = topicIndex[rawTopic] {
            for id in ids {
                if let entry = entries[id] {
                    matchedIDs.insert(id)
                    if let dispatch = makeDispatchIfAllowed(entry: entry, payload: payload) {
                        results.append(dispatch)
                    }
                }
            }
        }

        // 2. Wildcard match (scan les souscriptions wildcard).
        //    On ne scanne que les entrées dont le topic contient un wildcard.
        for (topicPath, ids) in topicIndex where topicPath.contains("+") || topicPath.contains("#") {
            // Éviter le double-match si le path exact est aussi un wildcard.
            let wildcardTopic = RealtimeTopic(topicPath)
            let incomingTopic = RealtimeTopic(rawTopic)

            if incomingTopic.matches(pattern: wildcardTopic) {
                for id in ids {
                    // Éviter les doublons si l'ID a déjà été matché en exact.
                    // Le test porte sur `matchedIDs` et non sur `results` : une
                    // souscription différée n'apparaît pas dans `results`, et
                    // serait sinon réexaminée — donc son payload écrasé deux fois.
                    guard !matchedIDs.contains(id),
                          let entry = entries[id] else {
                        continue
                    }
                    matchedIDs.insert(id)
                    if let dispatch = makeDispatchIfAllowed(entry: entry, payload: payload) {
                        results.append(dispatch)
                    }
                }
            }
        }

        return SubscriptionMatch(dispatches: results, matchedCount: matchedIDs.count)
    }

    // MARK: - Queries

    /// Nombre total de souscriptions actives.
    var activeCount: Int {
        entries.count
    }

    /// Nombre de souscriptions sur un topic spécifique.
    func count(for topic: RealtimeTopic) -> Int {
        topicIndex[topic.path]?.count ?? 0
    }

    /// Tous les tokens d'une feature (pour le batch cancel).
    func tokens(forFeature feature: String) -> [any RealtimeSubscriptionToken] {
        guard let ids = featureIndex[feature] else { return [] }
        return ids.compactMap { id in
            guard let entry = entries[id] else { return nil }
            return ConcreteSubscriptionToken(
                id: id,
                topic: entry.topic,
                feature: feature,
                registry: self
            )
        }
    }

    /// Tous les topics actifs avec leur QoS (pour le resubscribe après reconnexion).
    ///
    /// Retourne les topics path uniques avec le QoS le plus élevé
    /// si plusieurs souscriptions existent sur le même topic.
    func activeTopicsWithQoS() -> [(String, RealtimeQoS)] {
        var topicQoS: [String: RealtimeQoS] = [:]

        for entry in entries.values {
            let path = entry.topic.path
            if let existing = topicQoS[path] {
                // Garder le QoS le plus élevé.
                if entry.qos > existing {
                    topicQoS[path] = entry.qos
                }
            } else {
                topicQoS[path] = entry.qos
            }
        }

        return topicQoS.map { ($0.key, $0.value) }
    }

    /// `true` si au moins une souscription existe pour un topic.
    func hasSubscription(for topic: RealtimeTopic) -> Bool {
        topicIndex[topic.path]?.isEmpty == false
    }

    /// Snapshot diagnostic par topic (pour un écran de monitoring).
    func diagnostics() -> [RealtimeSubscriptionDiagnostic] {
        topicIndex.compactMap { path, ids -> RealtimeSubscriptionDiagnostic? in
            let topicEntries = ids.compactMap { entries[$0] }
            guard let first = topicEntries.first else { return nil }

            var highestQoS = first.qos
            for entry in topicEntries where entry.qos > highestQoS {
                highestQoS = entry.qos
            }

            return RealtimeSubscriptionDiagnostic(
                topicPath: path,
                subscriberCount: ids.count,
                qos: highestQoS,
                isWildcard: path.contains("+") || path.contains("#"),
                feature: first.topic.feature?.rawValue
            )
        }
        .sorted { $0.topicPath < $1.topicPath }
    }

    // MARK: - Private — Temporal Processing

    /// Crée un SubscriptionDispatch si la policy temporelle le permet.
    ///
    /// Pour les souscriptions avec throttle/debounce, vérifie si assez
    /// de temps s'est écoulé depuis le dernier yield.
    private func makeDispatchIfAllowed(entry: SubscriptionEntry, payload: Data) -> SubscriptionDispatch? {
        let now = Date()

        switch entry.buffering {
        case .throttle(let interval):
            // Throttle : au moins `interval` secondes entre deux yield.
            if let lastYield = entry.lastYieldTime,
               now.timeIntervalSince(lastYield) < interval {
                return nil  // Trop tôt → ignorer ce message.
            }
            // Mettre à jour le timestamp (mutation via la référence dans entries).
            entries[entry.id]?.lastYieldTime = now
            return SubscriptionDispatch(entry: entry)

        case .debounce(let interval):
            // Debounce : « le dernier gagne ». Chaque message écrase le payload
            // en attente ; le timer, armé une seule fois, émet ce qui reste
            // après `interval` de silence.
            entries[entry.id]?.pendingPayload = payload
            entries[entry.id]?.lastYieldTime = now

            if entry.debounceTask == nil {
                let entryID = entry.id
                entries[entry.id]?.debounceTask = Task { [weak self] in
                    try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    guard !Task.isCancelled, let self else { return }
                    await self.flushDebounce(entryID: entryID)
                }
            }
            return nil  // Ne pas yield maintenant — le timer le fera.

        case .unbounded, .bufferNewest, .bufferOldest:
            // Pas de traitement temporel — yield immédiatement.
            return SubscriptionDispatch(entry: entry)
        }
    }

    /// Émet le dernier payload reçu, après la période de silence.
    ///
    /// Décode et yield ici plutôt que de rendre un `SubscriptionDispatch` :
    /// l'appelant a passé son chemin depuis longtemps quand le timer se
    /// déclenche. L'entrée porte déjà le décodeur et la continuation, donc le
    /// registry a tout ce qu'il faut.
    private func flushDebounce(entryID: UUID) {
        guard var entry = entries[entryID],
              let payload = entry.pendingPayload else {
            entries[entryID]?.debounceTask = nil
            return
        }

        entry.pendingPayload = nil
        entry.debounceTask = nil
        entry.lastYieldTime = Date()
        entries[entryID] = entry

        do {
            let decoded = try entry.decoder(payload)
            entry.continuation.yield(decoded)
        } catch {
            // Un payload indécodable est perdu — mais il est dit. La version
            // précédente perdait *tous* les messages sans rien émettre.
            registryLog.error("Debounce flush failed to decode on topic \(entry.topic.path, privacy: .public)")
        }
    }

    // MARK: - Diagnostics

    /// Snapshot de l'état du registry (debugging/métriques).
    struct Snapshot: Sendable {
        let totalSubscriptions: Int
        let uniqueTopics: Int
        let features: [String]
        let wildcardSubscriptions: Int
    }

    func snapshot() -> Snapshot {
        let wildcardCount = entries.values.filter { $0.topic.isWildcard }.count
        return Snapshot(
            totalSubscriptions: entries.count,
            uniqueTopics: topicIndex.count,
            features: Array(featureIndex.keys),
            wildcardSubscriptions: wildcardCount
        )
    }
}

// MARK: - SubscriptionEntry

/// Entrée interne d'une souscription dans le registry.
struct SubscriptionEntry {

    /// Identifiant unique de la souscription.
    let id: UUID

    /// Topic souscrit (peut contenir des wildcards).
    let topic: RealtimeTopic

    /// QoS de la souscription.
    let qos: RealtimeQoS

    /// Stratégie de backpressure.
    let buffering: RealtimeBufferingPolicy

    /// Continuation type-erased pour yield les messages vers le stream de la feature.
    let continuation: AnyContinuation

    /// Décodeur type-erased : Data → Any.
    let decoder: @Sendable (Data) throws -> Any

    // MARK: - Temporal State (mutated by registry)

    /// Timestamp du dernier yield (pour throttle/debounce).
    var lastYieldTime: Date?

    /// Le dernier payload reçu, en attente d'émission par le debounce.
    ///
    /// **C'était un `Bool`.** Un drapeau dit qu'un message est arrivé ; il ne
    /// dit pas lequel. Le flush n'avait donc rien à émettre et toute
    /// souscription `.debounce` ne recevait jamais rien — sans erreur, sans log,
    /// pour toute la durée de vie de l'application.
    var pendingPayload: Data?

    /// Task du timer de debounce en cours.
    var debounceTask: Task<Void, Never>?
}

// MARK: - SubscriptionMatch

/// Ce qu'a donné la recherche de souscriptions pour un topic.
///
/// Deux nombres et non un tableau, parce que « aucune souscription » et « des
/// souscriptions dont aucune n'émet maintenant » sont deux situations
/// différentes que l'ancien code confondait : le registry filtrait les entrées
/// en debounce avant de rendre la liste, et le client concluait « Message on
/// unsubscribed topic » sur un topic parfaitement souscrit. Le log accusait le
/// serveur d'un défaut qui était ici.
struct SubscriptionMatch {

    /// Les souscriptions à servir immédiatement.
    let dispatches: [SubscriptionDispatch]

    /// Combien de souscriptions ont matché le topic, différées comprises.
    let matchedCount: Int

    /// Le topic n'est réellement souscrit par personne.
    var isUnsubscribed: Bool { matchedCount == 0 }

    /// Combien sont différées par une politique temporelle.
    var deferredCount: Int { matchedCount - dispatches.count }
}

// MARK: - SubscriptionDispatch

/// Résultat de matching prêt pour le dispatch dans la receive loop.
///
/// Le RealtimeClient utilise ça pour décoder et yield :
/// ```swift
/// for subscription in matching {
///     let decoded = try subscription.decode(payload)
///     subscription.yield(decoded)
/// }
/// ```
struct SubscriptionDispatch {
    let id: UUID
    let decode: @Sendable (Data) throws -> Any
    let yield: @Sendable (Any) -> Void

    init(entry: SubscriptionEntry) {
        self.id = entry.id
        self.decode = entry.decoder
        self.yield = { value in entry.continuation.yield(value) }
    }
}

// MARK: - ConcreteSubscriptionToken

/// Implémentation concrète du RealtimeSubscriptionToken (CoreKit).
///
/// Détenu par la feature (ViewModel, Repository).
/// Quand le token est cancel ou deinit, la souscription est retirée du registry.
final class ConcreteSubscriptionToken: RealtimeSubscriptionToken, @unchecked Sendable {

    // MARK: - Properties

    let id: UUID
    let topic: RealtimeTopic
    let feature: String?

    /// Référence faible vers le registry pour le cancel.
    private weak var _registry: (any AnyObject)?
    private let _registryRef: SubscriptionRegistry

    /// `true` tant que la souscription n'a pas été annulée.
    private var _isActive: Bool = true
    private let lock = NSLock()

    // MARK: - Init

    init(
        id: UUID,
        topic: RealtimeTopic,
        feature: String?,
        registry: SubscriptionRegistry
    ) {
        self.id = id
        self.topic = topic
        self.feature = feature
        self._registry = registry
        self._registryRef = registry
    }

    // MARK: - RealtimeSubscriptionToken

    var isActive: Bool {
        get async {
            lock.lock()
            defer { lock.unlock() }
            return _isActive
        }
    }

    func cancel() async {
        lock.lock()
        guard _isActive else {
            lock.unlock()
            return
        }
        _isActive = false
        lock.unlock()

        await _registryRef.remove(id: id)
    }

    // MARK: - Deinit Safety Net

    deinit {
        // Safety net : si le token meurt sans cancel explicite,
        // on tente de nettoyer. Ce n'est pas garanti de fonctionner
        // (deinit ne peut pas être async), mais c'est un filet.
        lock.lock()
        let wasActive = _isActive
        _isActive = false
        lock.unlock()

        if wasActive {
            let registry = _registryRef
            let tokenId = id
            Task {
                await registry.remove(id: tokenId)
            }
            #if DEBUG
            print("[RealtimeKit] ⚠️ SubscriptionToken deinit without cancel() — topic: \(topic.path)")
            #endif
        }
    }
}
