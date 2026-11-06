// MARK: - CoreKit/Realtime/RealtimeSubscriptionToken.swift
//
// Module  : CoreKit
// Rôle    : Gestion du lifecycle des souscriptions temps réel.
//           Aucun équivalent HTTP (les requêtes se terminent naturellement).
//           En realtime, un subscribe() vit indéfiniment — sans cancel explicite,
//           on accumule des souscriptions zombies qui consomment de la bande passante.
//
// Design  : Le token est retourné par subscribe() et détenu par le consommateur.
//           Quand le token est released (cancel ou deinit), le unsubscribe est déclenché.
//           Le SubscriptionRegistry dans RealtimeKit track tous les tokens actifs.
//
// Pattern : Inspiré de AnyCancellable (Combine) adapté au monde async/await.

import Foundation

// MARK: - RealtimeSubscriptionToken

/// Token représentant une souscription temps réel active.
///
/// Détenu par le consommateur (ViewModel, Repository). La souscription reste active
/// tant que le token existe. Appeler `cancel()` ou laisser le token mourir (deinit)
/// déclenche le unsubscribe automatique.
///
/// ```swift
/// actor ChatRepository {
///     private var tokens: [RealtimeSubscriptionToken] = []
///
///     func startListening() async throws {
///         let (stream, token) = try await realtime.subscribe(
///             to: topic, as: ChatMessage.self, buffering: .unbounded, qos: .atLeastOnce
///         )
///         tokens.append(token)
///
///         for await message in stream {
///             handle(message)
///         }
///     }
///
///     func cleanup() async {
///         for token in tokens {
///             await token.cancel()
///         }
///         tokens.removeAll()
///     }
/// }
/// ```
public protocol RealtimeSubscriptionToken: AnyObject, Sendable {

    /// Identifiant unique de cette souscription.
    var id: UUID { get }

    /// Topic auquel cette souscription est attachée.
    var topic: RealtimeTopic { get }

    /// Feature propriétaire de cette souscription (pour le batch cancel).
    var feature: String? { get }

    /// `true` si la souscription est toujours active.
    var isActive: Bool { get async }

    /// Annule la souscription et libère les ressources.
    ///
    /// Idempotent — appeler cancel() plusieurs fois est safe.
    /// Après cancel, l'AsyncStream associé se termine (yield nil).
    func cancel() async
}

// MARK: - SubscriptionGroup

/// Groupe de tokens pour le cancel en batch.
///
/// Utile dans les ViewModels qui gèrent plusieurs souscriptions simultanées.
///
/// ```swift
/// let group = SubscriptionGroup()
///
/// let (stream1, token1) = try await realtime.subscribe(...)
/// group.add(token1)
///
/// let (stream2, token2) = try await realtime.subscribe(...)
/// group.add(token2)
///
/// // Plus tard — cancel tout d'un coup :
/// await group.cancelAll()
/// ```
public final class SubscriptionGroup: Sendable {

    private let lock = NSLock()
    private var _tokens: [any RealtimeSubscriptionToken] = []

    public init() {}

    /// Ajoute un token au groupe.
    public func add(_ token: any RealtimeSubscriptionToken) {
        lock.lock()
        _tokens.append(token)
        lock.unlock()
    }

    /// Annule toutes les souscriptions du groupe et vide la collection.
    public func cancelAll() async {
        lock.lock()
        let snapshot = _tokens
        _tokens.removeAll()
        lock.unlock()

        for token in snapshot {
            await token.cancel()
        }
    }

    /// Nombre de tokens actuellement dans le groupe.
    public var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return _tokens.count
    }

    /// Retire les tokens qui ne sont plus actifs (nettoyage périodique).
    public func pruneInactive() async {
        lock.lock()
        let snapshot = _tokens
        lock.unlock()

        var active: [any RealtimeSubscriptionToken] = []
        for token in snapshot {
            if await token.isActive {
                active.append(token)
            }
        }

        lock.lock()
        _tokens = active
        lock.unlock()
    }
}
